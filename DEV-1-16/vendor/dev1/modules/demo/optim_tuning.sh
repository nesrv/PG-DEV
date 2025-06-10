#!/bin/bash

. ../lib
init

###############################################################################
start_here 10
h 'Настройки стоимости'

c 'Пример запроса с корректной оценкой кардинальности:'

s 1 "EXPLAIN (analyze, timing off) SELECT *
FROM bookings
WHERE book_ref < '9000';"

c 'Планировщик выбрал последовательное сканирование, и сделал это на основе полной информации.'

p

c 'Так ли удачно это решение? Проверим, скомандовав планировщику не использовать последовательное сканирование, если есть другие способы:'

s 1 "SET enable_seqscan = off; -- действует до конца сеанса"

c 'Аналогичные enable-параметры есть и для прочих способов соединения, методов доступа и многих других операций. Эти параметры довольно грубо вмешиваются в работу планировщика, но весьма полезны для отладки и экспериментов.'

DUMMY=`si 1 "EXPLAIN (analyze, timing off) SELECT * FROM bookings WHERE book_ref < '9000';"` # прогреть кеш - seqscan использует буферное кольцо

s 1 "EXPLAIN (analyze, timing off) SELECT *
FROM bookings
WHERE book_ref < '9000';"

c 'Результат, скорее всего, окажется в пользу индексного сканирования, поскольку все данные закешированы и произвольный доступ выполняется быстро. Такая же ситуация возможна при использовании быстрых SSD-дисков. Делать выводы на основании одного запроса неправильно, но систематическая ошибка должна послужить поводом к изменению глобальных настроек. В таком случае стоит либо уменьшить значение random_page_cost, чтобы планировщик не завышал стоимость индексного доступа, либо увеличить effective_cache_size, чтобы сделать индексное сканирование более привлекательным.'

s 1 "RESET enable_seqscan; -- отменяем"

###############################################################################
P 15
h 'Схема данных'

c 'Ссылочное ограничение целостности особенно важно при составном ключе. Пример точной оценки строк, которое будет получено в результате соединения:'

s 1 "EXPLAIN SELECT *
FROM ticket_flights tf
  JOIN boarding_passes bp ON tf.flight_id = bp.flight_id
                         AND tf.ticket_no = bp.ticket_no;"

c 'Однако если удалить внешний ключ, оценка становится неадекватной. Это еще одно проявление проблемы коррелированных предикатов:'

s 1 "BEGIN;"
s 1 "ALTER TABLE boarding_passes
DROP CONSTRAINT boarding_passes_ticket_no_fkey;"

s 1 "EXPLAIN SELECT *
FROM ticket_flights tf
  JOIN boarding_passes bp ON tf.flight_id = bp.flight_id
                         AND tf.ticket_no = bp.ticket_no;"

s 1 "ROLLBACK;"

###############################################################################
P 19
h 'Короткие запросы'

c 'Сразу отключим параллельное выполнение. Для коротких запросов оно бесполезно, а параллельные планы сложнее читать.' 

s 1 "SET max_parallel_workers_per_gather = 0;"

c 'Рассмотрим запрос, который выводит посадочные талоны, выданные на рейсы, отправляющиеся в течение часового интервала:'

s 1 "EXPLAIN (analyze, timing off) SELECT bp.*
FROM flights f
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id
WHERE date_trunc('hour',f.scheduled_departure) = '2017-06-01 12:00:00';"

c 'Этот запрос можно отнести к разряду коротких: из двух больших таблиц требуется гораздо меньше процента данных. Однако в плане мы видим, что таблицы читаются полностью. Кроме того, наблюдается большая разница между прогнозируемой и фактической кардинальностью.'

c 'Начнем оптимизацию с самого вложенного узла, Seq Scan по таблице рейсов flights. Из-за чего планировщик ошибается в оценке кардинальности?'

p

c 'Дело в функции date_trunc: для нее нет вспомогательной функции планировщика, поэтому берется фиксированная оценка селективности 5%. В темах «Базовая статистика» и «Расширенная статистика» мы исправляли подобные ситуации с помощью индекса по выражению и расширенной статистики. Но в данном случае достаточно переписать условие так, чтобы слева от оператора находилось поле таблицы:'

s 1 "EXPLAIN (analyze, timing off) SELECT *
FROM flights
WHERE scheduled_departure >= '2017-06-01 12:00:00'
  AND scheduled_departure <  '2017-06-01 13:00:00';"

c 'Теперь оценка больше похожа на правду, а запрос заодно стал использовать индекс. Хорошо ли это?'

p

c 'В целом хорошо, но индекс создан по столбцам flight_no и scheduled_departure, а условие есть только на второй столбец. В теме «Методы доступа» мы выяснили, что в этом случае индекс будет сканироваться полностью, что нельзя считать эффективным способом доступа к данным.'

c 'Создадим новый индекс:'

s 1 "CREATE INDEX ON flights(scheduled_departure);"

c 'Проверим наш запрос:'

s 1 "EXPLAIN (analyze, timing off) SELECT bp.*
FROM flights f
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id
WHERE f.scheduled_departure >= '2017-06-01 12:00:00'
  AND f.scheduled_departure <  '2017-06-01 13:00:00';"

c 'В принципе, мы достигли желаемого: планировщик использует индексный доступ, данные соединяются методом вложенного цикла. Проверим еще количество страниц, которые потребовалось прочитать:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off) SELECT bp.*
FROM flights f
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id
WHERE f.scheduled_departure >= '2017-06-01 12:00:00'
  AND f.scheduled_departure <  '2017-06-01 13:00:00';"

c 'Возможным улучшением будет исключение доступа к таблице flights за счет сканирования только индекса. Удалим созданный ранее индекс и сделаем другой с дополнительным столбцом, который нужен для соединения:'

s 1 "DROP INDEX flights_scheduled_departure_idx;"
s 1 "CREATE INDEX ON flights(scheduled_departure, flight_id);"

s 1 "EXPLAIN (analyze, buffers, costs off, timing off) SELECT bp.*
FROM flights f
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id
WHERE f.scheduled_departure >= '2017-06-01 12:00:00'
  AND f.scheduled_departure <  '2017-06-01 13:00:00';"

c 'Мы выиграли еще около 20% чтений. Это может быть важно для запросов, которые выполняются часто, но вряд ли это наш случай. Скорее всего, включение в индекс всех полей таблицы boarding_passes будет избыточным — накладные расходы перевесят выигрыш в производительности. Остановимся на достигнутом.'

###############################################################################
P 21
h 'Длинные запросы'

c 'Задача: посчитать количество пассажиров, летевших рейсами, и вылет, и прибытие которых состоялись с опозданием от одной минуты до четырех часов.'

c 'Вот запрос, решающий задачу, но время его выполнения нас не устраивает:'

s 1 "\timing on"
s 1 "SELECT count(*) 
FROM flights f 
  JOIN ticket_flights tf ON tf.flight_id = f.flight_id
  JOIN boarding_passes bp ON bp.flight_id = tf.flight_id AND bp.ticket_no = tf.ticket_no
WHERE f.actual_departure - f.scheduled_departure BETWEEN interval '1 min' AND interval '4 hours'
  AND f.actual_arrival - f.scheduled_arrival BETWEEN interval '1 min' AND interval '4 hours';"
s 1 "\timing off"

c 'Короткий это запрос или длинный?'

c 'Узнаем селективность условий:'

s 1 "SELECT count(*) FROM flights f;"
s 1 "SELECT count(*) FROM flights f
WHERE f.actual_departure - f.scheduled_departure BETWEEN interval '1 min' AND interval '4 hours'
  AND f.actual_arrival - f.scheduled_arrival BETWEEN interval '1 min' AND interval '4 hours';"

c 'Условия отбирают примерно 80% строк, все таблицы в запросе большие. Очевидно, это длинный запрос.'

c 'Проверим его план:'

s 1 "EXPLAIN
SELECT count(*) 
FROM flights f 
  JOIN ticket_flights tf ON tf.flight_id = f.flight_id
  JOIN boarding_passes bp ON bp.flight_id = tf.flight_id AND bp.ticket_no = tf.ticket_no
WHERE f.actual_departure - f.scheduled_departure BETWEEN interval '1 min' AND interval '4 hours'
  AND f.actual_arrival - f.scheduled_arrival BETWEEN interval '1 min' AND interval '4 hours';"

c 'Здесь мы видим индексный доступ и соединения вложенным циклом — операции, совсем не подходящие для длинного запроса. Почему так получилось?'

p

c 'Проблема в ошибке оценки селективности условий. Планировщик считает, что из таблицы flights будет выбрано всего пять строк.'

c 'Попробуем быстро проверить гипотезу, что переход на другой способ соединения поможет делу. Попросим планировщик не использовать вложенный цикл, если это возможно:'

s 1 "SET enable_nestloop = off;"

s 1 "EXPLAIN (analyze, buffers, timing off, costs off)
SELECT count(*) 
FROM flights f 
  JOIN ticket_flights tf ON tf.flight_id = f.flight_id
  JOIN boarding_passes bp ON bp.flight_id = tf.flight_id AND bp.ticket_no = tf.ticket_no
WHERE f.actual_departure - f.scheduled_departure BETWEEN interval '1 min' AND interval '4 hours'
  AND f.actual_arrival - f.scheduled_arrival BETWEEN interval '1 min' AND interval '4 hours';"

c 'Обращения к таблицам автоматически сменились на последовательное чтение. Запрос ускорился, ему потребовалось прочитать примерно 130 тысяч блоков (против 29 миллионов у первой версии!).'

s 1 "RESET enable_nestloop;"

c 'Нам осталось более аккуратно объяснить планировщику, какой план стоит использовать. Самый мягкий способ — предоставить более точную статистику. В данном случае подойдет статистика по выражению, которую мы рассматривали в теме «Расширенная статистика»:'

s 1 "CREATE STATISTICS ON (actual_departure - scheduled_departure) FROM flights;"
s 1 "CREATE STATISTICS ON (actual_arrival - scheduled_arrival) FROM flights;"
s 1 "ANALYZE flights;"

c 'Проверим план:'

s 1 "EXPLAIN
SELECT count(*) 
FROM flights f 
  JOIN ticket_flights tf ON tf.flight_id = f.flight_id
  JOIN boarding_passes bp ON bp.flight_id = tf.flight_id AND bp.ticket_no = tf.ticket_no
WHERE f.actual_departure - f.scheduled_departure BETWEEN interval '1 min' AND interval '4 hours'
  AND f.actual_arrival - f.scheduled_arrival BETWEEN interval '1 min' AND interval '4 hours';"

c 'Оценки исправились, теперь во всех узлах они довольно точно соответствуют реальным цифрам. Однако планировщик выбрал не тот план, что мы видели: он перестал использовать соединение вложенным циклом, но оставил индексный доступ и применил соединение слиянием. В результате запрос стал выполняться еще быстрее, хотя ему и потребовалось прочитать более двух миллионов страниц. Хорошо это или плохо?'

p

c 'Это зависит от обстоятельств. Если мы уверены, что размера кеша хватит, чтобы в нем находились данные наших крупных таблиц — хорошо. В конце концов, запрос действительно стал выполняться быстрее! Однако в реальной системе за кеш будут конкурировать данные многих таблиц. Если реальное обращение к страницам окажется медленнее ожидаемого, это повод вернуться к настройкам сервера БД с помощью параметров random_page_cost и effective_cache_size.'

p

c 'Однако зададимся вопросом: не читаем ли мы лишние данные? Знание предметной области позволяет нам прийти к выводу,  что таблица ticket_flights вовсе не нужна в запросе. Таблицу flights можно соединить непосредственно с boarding_passes — внешние ключи проверяют корректность данных, но не требуются для соединения. Добавление ticket_flights никак не ограничивает данные (не может быть ситуации, при которой посадочный талон есть, а перелет отсутствует).'

c 'Вообще, переформулирование запроса — самый разнообразный и вариативный способ влияния на производительность. Некоторые эквивалентные преобразования планировщик умеет выполнять сам, но мы можем:'

ul 'переписать условия так, чтобы они могли (или наоборот, не могли) использовать индекс;'
ul 'заменить коррелированные подзапросы (которые, по сути, являются вложенным циклом) соединениями;'
ul 'устранить лишние сканирования (как в этом примере, или, скажем, за счет применения оконных функций);'
ul 'использовать недоступные планировщику трансформации, такие, как преобразование условий OR в UNION;'
ul 'и т. п.'

c 'Итак, упрощаем запрос:'

s 1 "EXPLAIN (analyze, buffers, timing off, costs off)
SELECT count(*) 
FROM flights f 
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id
WHERE f.actual_departure - f.scheduled_departure BETWEEN interval '1 min' AND interval '4 hours'
  AND f.actual_arrival - f.scheduled_arrival BETWEEN interval '1 min' AND interval '4 hours';"

c 'Потребовалось прочитать всего 61 тысячу страниц. Проверим, сколько всего страниц в таблицах:'

s 1 "SELECT sum(relpages) FROM pg_class
WHERE relname IN ('flights','boarding_passes');"

c 'Теперь мы уверены, что не читаем лишних данных.'

c 'Можно ли еще что-то улучшить?'

p

c 'План запроса говорит о том, что выполнялось двухпроходное соединение хешированием. Можно увеличить значение параметра work_mem, чтобы хеш-соединению было достаточно одного прохода без временных файлов.'

s 1 "SET work_mem = '8MB'; -- имеет смысл увеличить для всего сервера"

s 1 "EXPLAIN (analyze, timing off, costs off)
SELECT count(*) 
FROM flights f 
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id
WHERE f.actual_departure - f.scheduled_departure BETWEEN interval '1 min' AND interval '4 hours'
  AND f.actual_arrival - f.scheduled_arrival BETWEEN interval '1 min' AND interval '4 hours';"

c 'В начале темы мы отключали параллельные планы. Однако для длинных запросов параллельные планы могут иметь смысл. Конечно, при условии наличия свободных ядер, как рассматривалось в теме «Параллельный доступ». Посмотрим:'

s 1 "RESET max_parallel_workers_per_gather;"

s 1 "EXPLAIN (analyze, timing off, costs off)
SELECT count(*) 
FROM flights f 
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id
WHERE f.actual_departure - f.scheduled_departure BETWEEN interval '1 min' AND interval '4 hours'
  AND f.actual_arrival - f.scheduled_arrival BETWEEN interval '1 min' AND interval '4 hours';"

c 'Мы видим, что планировщик использует параллельный план, но в виртуальной машине с одним ядром он, конечно, не дает никаких преимуществ.'

###############################################################################
stop_here
cleanup
demo_end
