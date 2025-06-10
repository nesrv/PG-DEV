#!/bin/bash

. ../lib
init

start_here 5

###############################################################################
h 'Перенос статистики модулем dump_stat'

c 'Создадим таблицу по образцу bookings.flights и соберем статистику.'
s 1 "\c demo"
s 1 "CREATE TABLE public.flights
AS SELECT * FROM bookings.flights;"
s 1 "ANALYZE public.flights;"
s 1 "SELECT attname, null_frac, avg_width, n_distinct
FROM pg_stats
WHERE tablename = 'flights' AND schemaname = 'public';"

c 'Подключим расширение dump_stat'
s 1 "CREATE EXTENSION dump_stat;"

c 'Перегруженная функция dump_statistic позволяет выгрузить статистику по всей базе данных, по строкам отношений в заданной схеме или по конкретной таблице.'
c 'Выгрузим статистику по таблице public.flights:'
s 1 "COPY (SELECT dump_statistic('public','flights')) TO '/tmp/flights.stat';"

c 'Теперь удалим таблицу и создадим ее заново, но с выключенной автоочисткой, чтобы исключить автоматический сбор статистики.'
s 1 "DROP TABLE public.flights;"
s 1 "CREATE TABLE public.flights
WITH (autovacuum_enabled = off)
AS SELECT * FROM bookings.flights;"

c 'Статистики пока нет:'
s 1 "SELECT attname, null_frac, avg_width, n_distinct
FROM pg_stats
WHERE tablename = 'flights' AND schemaname = 'public';"

c 'Загрузим сохраненную ранее статистику:'
s 1 "\i /tmp/flights.stat"

s 1 "SELECT attname, null_frac, avg_width, n_distinct
FROM pg_stats WHERE tablename = 'flights' and schemaname = 'public';"

c 'Статистика успешно загрузилась. Расширение далее не требуется.'
s 1 "DROP EXTENSION dump_stat;"

P 8
###############################################################################
h 'Отслеживание планов запросов активных сеансов'

c 'Подключим расширение и соответствующую разделяемую библиотеку.'
s 1 "\c demo"
s 1 "CREATE EXTENSION pg_query_state;"
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_query_state';"

c 'Необходима перезагрузка экземпляра.'
pgctl_restart A
psql_open A 1 demo

c 'Откроем еще один сеанс:'
psql_open A 2 demo

c 'Номер обслуживающего процесса второго сеанса:'
s 2 "SELECT * FROM pg_backend_pid();"

c 'Запустим во втором сеансе запрос. Запрос написан таким образом, что перебирает в цикле все перелеты из таблицы ticket_flights и для каждого из них выбирает номер бронирования из таблицы tickets. В данном случае это очень неэффективный способ получения результата, но большое время выполнения запроса позволит отследить в первом сеансе ход его выполнения.'

c 'Мы выведем оценку стоимости и кардинальности (аналогичную той, что выдает команда EXPLAIN) и актуальную информацию о выполнении узлов плана.'
ss 2 "SELECT tf.*, (SELECT t.book_ref FROM tickets t WHERE t.ticket_no = tf.ticket_no)
FROM ticket_flights tf;"

si 1 "SELECT plan FROM pg_query_state($PID2, costs => true);"
c 'Небольшая пауза...'
sleep 1
si 1 "SELECT plan FROM pg_query_state($PID2, costs => true);"

c 'Сравните для узла Seq Scan прогноз числа строк (rows) с актуальной информацией (Current loop: rows). Таким образом можно обоснованно предположить, какая часть работы уже проделана.'
c 'Вложенный узел Index Scan выполняется в цикле. Для него выводится среднее значение по прошедшим циклам (actual, по аналогии с выводом команды EXPLAIN ANALYZE) и информация о текущем, еще не завершенном цикле (Current loop).'

p

c 'Как и команда EXPLAIN ANALYZE, расширение позволяет выводить информацию о времени выполнения узлов и о количестве использованных буферов, а также отслеживать параллельные запросы и запросы, выполняющиеся в вызываемых функциях.'

c 'Удалим расширение и перезапустим экземпляр.'
s 1 'DROP EXTENSION pg_query_state;'
s 1 "ALTER SYSTEM RESET shared_preload_libraries;"
pgctl_restart A

###############################################################################
P 13
h 'Модуль pg_hint_plan'

c 'Расширение pg_hint_plan предоставляется вместе с Postgres Pro Enterprise в виде отдельного пакета, который устанавливается средствами ОС из репозитория. В виртуальной машине, предназначенной для курса, этот пакет уже установлен.'
c 'Так как функционал расширения реализован в разделяемой библиотеке, она должна быть предварительно загружена в сеансе с помощью команды LOAD или настроена глобально в конфигурационном параметре shared_preload_libraries.'
psql_open A 1 demo
s 1 "LOAD 'pg_hint_plan';"

c 'Для данного запроса используется параллельный план с двумя рабочими процессами:'
s 1 "EXPLAIN (costs off) SELECT count(*) FROM ticket_flights;"

c 'Для управления параллелизмом применяется указание Parallel. С параметром hard оно принудительно задает количество процессов.'
c 'В этом примере мы отключаем параллельное выполнение, указывая ноль:'

s 1 "/*+ Parallel(ticket_flights 0 hard) */
EXPLAIN (costs off) SELECT count(*) FROM ticket_flights;"

c 'Принудительно установим три рабочих процесса:'

s 1 "/*+ Parallel(ticket_flights 3 hard) */
EXPLAIN (costs off) SELECT count(*) FROM ticket_flights;"

c 'Параметр soft лишь меняет значение параметра max_parallel_workers_per_gather, а в остальном планировщику остается свобода выбора. В данном случае планировщик ограничился двумя процессами из-за относительного небольшого размера таблицы:'
s 1 "/*+ Parallel(ticket_flights 3 soft) */
EXPLAIN (costs off) SELECT count(*) FROM ticket_flights;"

p

c 'Указание Leading позволяет влиять на порядок соединений.'

c 'Теперь поменяем порядок соединений. Если указаны двойные скобки, то задается не только порядок, но и направление (внешняя таблица и внутренняя таблица) соединений:'

s 1 "/*+ Leading((t (tf f))) */
EXPLAIN (costs off)
SELECT t.passenger_name, tf.flight_id, f.flight_no
FROM tickets t, ticket_flights tf, flights f
WHERE t.ticket_no = tf.ticket_no AND tf.flight_id = f.flight_id ;"

c 'Попробуем другой порядок:'

s 1 "/*+ Leading(((tf f) t)) */
EXPLAIN (costs off)
SELECT t.passenger_name, tf.flight_id, f.flight_no
FROM tickets t, ticket_flights tf, flights f
WHERE t.ticket_no = tf.ticket_no AND tf.flight_id = f.flight_id ;"

c 'Часто достаточно указать лишь несколько начальных таблиц, оставив планировщику свободу выбора для остальных соединений. В этом примере планировщик начнет с соединения таблиц f и tf, и поскольку пара помещена в одинарные скобки, сможет сам выбрать направление соединения:'

s 1 "/*+ Leading(f tf) */
EXPLAIN (costs off)
SELECT t.passenger_name, tf.flight_id, f.flight_no
FROM tickets t, ticket_flights tf, flights f
WHERE t.ticket_no = tf.ticket_no AND tf.flight_id = f.flight_id ;"

p

c 'В предыдущих примерах для добавления указаний пришлось редактировать тексты запросов. Если это невозможно, удобно использовать таблицу hint_plan.hints, она создается при добавлении расширения в базу данных.'

s 1 "CREATE EXTENSION pg_hint_plan;"

c 'Возьмем запрос с индексным доступом:'
s 1 "EXPLAIN (costs off)
SELECT * FROM bookings WHERE book_ref = 'CDE08B';"

c 'Поместим в таблицу указаний требование использовать последовательное сканирование.'
c 'Константы, фигурирующие в целевом запросе, в столбце norm_query_string таблицы hint_plan.hints должны заменяться знаками «?». В остальном текст запроса должен посимвольно совпадать, включая переводы строк:'

s 1 "INSERT INTO hint_plan.hints (norm_query_string, application_name, hints)
VALUES (
  E'EXPLAIN (costs off)\nSELECT * FROM bookings WHERE book_ref = ?;',
  'psql',
  'SeqScan(bookings)'
);"

c 'Включим использование таблицы указаний:'
s 1 "SET pg_hint_plan.enable_hint_table TO on;"

c 'Теперь план запроса содержит последовательное сканирование:'
s 1 "EXPLAIN (costs off)
SELECT * FROM bookings WHERE book_ref = 'CDE08B';"

c 'Отключим расширение.'
s 1 "DROP EXTENSION pg_hint_plan;"

###############################################################################
P 15
h 'Модуль plantuner'

c 'Пусть таблица ticket_flights имеет индексы по стоимости билета и по классу обслуживания:'
psql_open A 1 demo
s 1 "CREATE INDEX ticket_flights_amount_idx ON ticket_flights(amount);"
s 1 "CREATE INDEX ticket_flights_fare_conditions_idx ON ticket_flights(fare_conditions);"

QUERY=$(
cat <<"SQL"
EXPLAIN (costs off)
SELECT avg(amount)
FROM ticket_flights
WHERE fare_conditions=:'fare' and amount>50000;
SQL
)

c 'Следующий запрос будет использовать индекс по стоимости для любого класса обслуживания:'
s 1 "\set fare Business"
s 1 "$QUERY"
s 1 "\set fare Economy"
s 1 "$QUERY"

c 'Расширение plantuner позволяет исключить из рассмотрения индекс по стоимости, сохранив при этом возможность выбора метода доступа:'

s 1 "LOAD 'plantuner';"
s 1 "SET plantuner.disable_index='ticket_flights_amount_idx';"

c 'Если в запросе есть предикат с высокой селективностью, буден выбран другой индекс:'
s 1 "\set fare Business"
s 1 "$QUERY"

c 'А если селективность низкая, планировщик выбирает полное сканирование:'
s 1 "\set fare Economy"
s 1 "$QUERY"

c 'Следует понимать, что указания оптимизатору, как правило, дают эффект лишь в частных случаях: при определенных значениях констант и определенном состоянии данных в таблицах.'

###############################################################################

stop_here
cleanup
demo_end
