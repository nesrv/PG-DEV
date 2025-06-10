#!/bin/bash

. ../lib
init

start_here 5

###############################################################################

h 'Число строк'

c 'Начнем с оценки кардинальности в простом случае запроса без предикатов.'

s 1 "EXPLAIN
SELECT * FROM flights;"

c 'Точное значение:'

s 1 "SELECT count(*) FROM flights;"

p

c 'Оптимизатор получает значение из pg_class:'

s 1 "SELECT reltuples, relpages FROM pg_class WHERE relname = 'flights';"
ROWS=`s_bare 1 "SELECT reltuples FROM pg_class WHERE relname = 'flights';"`

c 'Значение параметра, управляющего ориентиром статистики, по умолчанию равно 100:'

s 1 "SHOW default_statistics_target;"

c 'Поскольку при анализе таблицы учитывается 300 × default_statistics_target строк, то оценки для относительно крупных таблиц могут не быть абсолютно точными.'

p

###############################################################################
h 'Доля неопределенных значений'

c 'Часть рейсов еще не отправились, поэтому время вылета для них не определено:'

s 1 "EXPLAIN
SELECT * FROM flights WHERE actual_departure IS NULL;"

c 'Точное значение:'

s 1 "SELECT count(*) FROM flights WHERE actual_departure IS NULL;"

p

c 'Оценка оптимизатора получена как общее число строк, умноженное на долю NULL-значений:'

s 1 "SELECT $ROWS * null_frac FROM pg_stats
WHERE tablename = 'flights' AND attname = 'actual_departure';"

p

###############################################################################
h 'Число уникальных значений'

c 'Проверим количество моделей самолетов в таблице рейсов:'

s 1 "SELECT n_distinct FROM pg_stats 
WHERE tablename = 'flights' AND attname = 'aircraft_code';"

c 'Это соответствует действительности:'

s 1 "SELECT count(DISTINCT aircraft_code) FROM flights;"

c 'А в таблице самих самолетов?'

s 1 "SELECT n_distinct FROM pg_stats 
WHERE tablename = 'aircrafts_data' AND attname = 'aircraft_code';"

c 'Здесь значение -1 говорит о том, что каждое значение является уникальным. Это неудивительно, ведь aircraft_code является первичным ключом в этой таблице.'

p

###############################################################################
h 'Кардинальность соединения'

c 'Селективность соединения — доля строк от декартова произведения двух таблиц, которая остается после применения условия соединения.'

c 'Поэтому для расчета кардинальности соединения оптимизатор оценивает кардинальность декартова произведения и умножает его на селективность условия соединения (и на селективность условий фильтров, если они есть).'

c 'Рассмотрим пример:'

s 1 "EXPLAIN SELECT *
FROM flights f
  JOIN aircrafts a ON a.aircraft_code = f.aircraft_code;"

p

c 'Точное значение кардинальности:'

s 1 "SELECT count(*)
FROM flights f 
  JOIN aircrafts a ON a.aircraft_code = f.aircraft_code;"

p

c 'Базовая формула для расчета селективности соединения (в предположении равномерного распределения) — минимальное из значений 1/nd1 и 1/nd2, где'
ul 'nd1 — число уникальных значений ключа соединения в первом наборе строк;'
ul 'nd2 — число уникальных значений ключа соединения во втором наборе строк.'

ND_A=`s_bare 1 "SELECT n_distinct FROM pg_stats WHERE tablename = 'flights' and attname = 'aircraft_code';"`
ROWS_A=`s_bare 1 "SELECT count(*) FROM aircrafts;"`
ROWS_S=`s_bare 1 "SELECT count(*) FROM seats;"`

p

c 'В данном случае получаем ровно то, что требуется:'

s 1 "SELECT round($ROWS * $ROWS_A * least(1.0/$ND_A, 1.0/$ROWS_A));"

P 7

###############################################################################

h 'Наиболее частые значения'

c 'Для эксперимента ограничим размер списка наиболее частых значений (который по умолчанию определяется параметром default_statistics_target) на уровне столбца:'

s 1 "ALTER TABLE flights
ALTER COLUMN arrival_airport
SET STATISTICS 10;"
s 1 "ANALYZE flights;"

c 'Если значение попало в список наиболее частых, селективность можно узнать непосредственно из статистики. Пример (Шереметьево):'

s 1 "EXPLAIN
SELECT * FROM flights WHERE arrival_airport = 'SVO';"

c 'Точное значение:'

s 1 "SELECT count(*) FROM flights WHERE arrival_airport = 'SVO';"

p

c 'Вот как выглядит список наиболее частых значений и частота их встречаемости:'

s 1 "SELECT most_common_vals, most_common_freqs
FROM pg_stats
WHERE tablename = 'flights' AND attname = 'arrival_airport' \gx"

p

c 'Кардинальность вычисляется как число строк, умноженное на частоту значения:'

s 1 "SELECT $ROWS * s.most_common_freqs[array_position((s.most_common_vals::text::text[]),'SVO')]
FROM pg_stats s
WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport';"

c 'Список наиболее частых значений может использоваться и для оценки селективности неравенств. Для этого в most_common_vals надо найти все значения, удовлетворяющие неравенству, и просуммировать частоты соответствующих элементов из most_common_freqs.'

p

c 'Если же указанного значения нет в списке наиболее частых, то селективность вычисляется исходя из предположения, что все данные (кроме наиболее частых) распределены равномерно.'
c 'Например, в списке частых значений нет Владивостока.'

s 1 "EXPLAIN
SELECT * FROM flights WHERE arrival_airport = 'VVO';"

c 'Точное значение:'

s 1 "SELECT count(*) FROM flights WHERE arrival_airport = 'VVO';"

p

c 'Для получения оценки вычислим сумму частот наиболее частых значений:'

s 1 "SELECT sum(f) FROM pg_stats s, unnest(s.most_common_freqs) f
  WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport';"

MCF=`s_bare 1 "SELECT sum(f) FROM pg_stats s, unnest(s.most_common_freqs) f WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport';"`

p

c 'На менее частые значения приходятся оставшиеся строки. Поскольку мы исходим из предположения о равномерности распределения менее частых значений, селективность будет равна 1/nd, где nd — число уникальных значений:'

s 1 "SELECT n_distinct
FROM pg_stats s
WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport';"

ND=`s_bare 1 "SELECT n_distinct FROM pg_stats s WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport';"`

p

c 'Учитывая, что из этих значений 10 входят в список наиболее частых, а неопределенных значений нет, получаем следующую оценку:'

s 1 "SELECT $ROWS * (1 - $MCF) / ($ND - 10);"

P 10

###############################################################################

h 'Гистограмма'

c 'При условиях «больше» и «меньше» для оценки будет использоваться список наиболее частых значений, или гистограмма, или оба способа вместе. Гистограмма строится так, чтобы не включать наиболее частые значения и NULL:'

s 1 "SELECT histogram_bounds
FROM pg_stats s
WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport';"

HB=`s_bare 1 "SELECT hb FROM pg_stats s, unnest(s.histogram_bounds::text::text[]) WITH ordinality hb WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport' AND hb.ordinality = 3;"`

c 'Число корзин гистограммы определяется параметром default_statistics_target, а границы выбираются так, чтобы в каждой корзине находилось примерно одинаковое количество значений.'

p

c 'Рассмотрим пример:'

s 1 "EXPLAIN
SELECT * FROM flights WHERE arrival_airport <= '$HB';"

c 'Точное значение:'

s 1 "SELECT count(*) FROM flights WHERE arrival_airport <= '$HB';"

p

c 'Как получена оценка?'
c 'Учтем частоту наиболее частых значений, попадающих в указанный интервал:'

s 1 "SELECT sum( s.most_common_freqs[array_position((s.most_common_vals::text::text[]),v)] )
FROM pg_stats s, unnest(s.most_common_vals::text::text[]) v
WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport' AND v <= '$HB';"

MCF2=`s_bare 1 "SELECT sum( s.most_common_freqs[array_position((s.most_common_vals::text::text[]),v)] ) FROM pg_stats s, unnest(s.most_common_vals::text::text[]) v WHERE s.tablename = 'flights' AND s.attname = 'arrival_airport' AND v <= '$HB';"`

p

c 'Указанный интервал занимает ровно 2 корзины гистограммы из 10, а неопределенных значений в данном столбце нет, получаем следующую оценку:'

s 1 "SELECT $ROWS * (
	$MCF2 + (1 - $MCF) * (2.0 / 10.0)
);"

c 'В общем случае учитываются и не полностью занятые корзины (с помощью линейной аппроксимации).'

p

###############################################################################
h 'Кардинальность соединения'

c 'В случае неравномерного распределения данных в ключах соединения базовая формула расчета селективности соединения (минимальное из значений 1/nd1 и 1/nd2) дает неправильный результат. Например, рейсы совершают разные модели самолетов с разной вместимостью, и для соединения рейсов с местами мы получили бы:'

s 1 "SELECT round($ROWS * $ROWS_S * least(1.0/$ND_A, 1.0/$ND_A));"

c 'При этом точное значение в два раза меньше:'

s 1 "SELECT count(*)
FROM flights f 
  JOIN seats s ON f.aircraft_code = s.aircraft_code;"

p

c 'Однако планировщик умеет учитывать списки наиболее частых значений и гистограммы, и получает практически точную оценку:'

s 1 "EXPLAIN SELECT *
FROM flights f
  JOIN seats s ON f.aircraft_code = s.aircraft_code;"

p

c 'К сожалению, ситуация ухудшается, когда соединяются несколько таблиц. Например, добавим в предыдущий запрос таблицу самолетов — это никак не повлияет на общее количество строк в выборке:'

s 1 "SELECT count(*)
FROM flights f
  JOIN aircrafts a ON a.aircraft_code = f.aircraft_code
  JOIN seats s ON a.aircraft_code = s.aircraft_code;"

p

c 'Однако теперь планировщик ошибается:'

s 1 "EXPLAIN
SELECT *
FROM flights f
  JOIN aircrafts a ON a.aircraft_code = f.aircraft_code
  JOIN seats s ON a.aircraft_code = s.aircraft_code;"

c 'Дело в том, что, соединив первые две таблицы, планировщик не имеет детальной статистики о результирующем наборе строк. Во многих случаях именно это является основной причиной плохих оценок.'

P 13

###############################################################################

h 'Элементы составных полей'

c 'Для примера рассмотрим таблицу pg_constraint — в ней хранятся ограничения целостности, определенные для таблиц. И в ней есть поле conkey с массивом номеров столбцов, образующих ограничение:'

s 1 "SELECT conname, conkey
FROM pg_constraint
WHERE conname LIKE 'boarding%';"

c 'Для этого поля можно получить наиболее частые значения и их частоты. Чтобы было удобнее просматривать статистику, соберем ее с уменьшенным значением ориентира:'

s 1 "SET default_statistics_target = 7;"
s 1 "ANALYZE pg_constraint;"

s 1 "SELECT most_common_vals, most_common_freqs
FROM pg_stats
WHERE tablename = 'pg_constraint' AND attname = 'conkey' \gx"

c 'В данном случае значения в столбце — это массивы элементов. Такая статистика не позволит оценить кардинальность, например, для условия вхождения элемента в массив. Однако планировщик не ошибается в оценке:'

s 1 "SELECT count(*) 
FROM pg_constraint 
WHERE conkey @> ARRAY[2::smallint];"

s 1 "EXPLAIN SELECT * 
FROM pg_constraint 
WHERE conkey @> ARRAY[2::smallint];"

c 'Для таких условий используется статистика по отдельным элементам:'

s 1 "SELECT most_common_elems, most_common_elem_freqs, elem_count_histogram
FROM pg_stats 
WHERE tablename = 'pg_constraint' AND attname = 'conkey' \gx"

c 'Для частот и гистограмм в конце массива содержится дополнительная информация (минимум, максимум, среднее), поэтому количество значений превышает установленный ориентир.'

p

freq2=$(s_bare 1 \
	"SELECT most_common_elem_freqs[array_position((most_common_elems::text::smallint[]),2)]
	FROM (
		SELECT most_common_elems, most_common_elem_freqs
		FROM pg_stats WHERE tablename = 'pg_constraint' AND attname = 'conkey'
	);" \
)

c 'Планировщик получает оценку, используя частоту элемента 2:'

s 1 "SELECT $freq2 * reltuples rows
FROM pg_class 
WHERE relname = 'pg_constraint';"

s 1 "RESET default_statistics_target;"
s 1 "ANALYZE pg_constraint;"

P 15

###############################################################################

h 'Частные и общие планы'

c 'Подготовим запрос и создадим индекс:'

s 1 "PREPARE f(text) AS
SELECT * FROM flights WHERE status = \$1;"

s 1 "CREATE INDEX ON flights(status);"

c 'Поиск отмененных рейсов будет использовать индекс, поскольку статистика говорит о том, что таких рейсов мало:'

s 1 "EXPLAIN EXECUTE f('Cancelled');"

c 'А поиск прибывших рейсов — нет, поскольку их много:'

s 1 "EXPLAIN EXECUTE f('Arrived');"

c 'Такие планы называются частными, поскольку они построены с учетом конкретных значений параметров.'

p

c 'Однако планировщик строит и общий план без учета конкретных значений параметров. Если в какой-то момент оказывается, что стоимость общего плана не превышает среднюю стоимость уже построенных ранее частных планов, планировщик начинает пользоваться общим планом, больше не выполняя планирование. Но первые пять раз используются частные планы, чтобы накопить статистику.'

c 'Выполним оператор еще три раза:'

s 1 "EXPLAIN EXECUTE f('Arrived');"
s 1 "EXPLAIN EXECUTE f('Arrived');"
s 1 "EXPLAIN EXECUTE f('Arrived');"

c 'Количество выполнений общего и частных планов можно посмотреть в представлении pg_prepared_statements:'

s 1 "SELECT name, generic_plans, custom_plans
FROM pg_prepared_statements;"

c 'В следующий раз планировщик переключится на общий план. Вместо конкретного значения в плане будет указан номер параметра:'

s 1 "EXPLAIN EXECUTE f('Arrived');"

s 1 "SELECT name, generic_plans, custom_plans
FROM pg_prepared_statements;"

p

c 'Имея текст запроса с параметрами, представленными номерами (например, из журнала сообщений сервера), можно посмотреть общий план такого запроса следующим образом:'

s 1 "EXPLAIN (generic_plan)
SELECT * FROM flights WHERE status = \$1;"

p

c 'Переход на общий план может быть нежелателен в случае неравномерного распределения значений. Параметр plan_cache_mode позволяет отключить использование частных планов (или наоборот, с самого начала использовать общий план):'

s 1 "SHOW plan_cache_mode;"
s 1 "SET plan_cache_mode = 'force_custom_plan';"
s 1 "EXPLAIN EXECUTE f('Arrived');"

s 1 "RESET plan_cache_mode;"

p
###############################################################################

h 'Частичный индекс'

c 'Поиск уже прибывших рейсов будет выполняться последовательным сканированием таблицы flights, поэтому индексные записи с ключом Arrived никогда не используются. При этом они занимают место и требуют ресурсов для синхронизации с изменениями строк таблицы.'

c 'Можно поместить в индекс только ссылки на строки, удовлетворяющие условиям с высокой селективностью:'
s 1 "CREATE INDEX on flights(status)
WHERE status IN ('Delayed', 'Departed', 'Cancelled');"

c 'Размер частичного индекса существенно меньше, чем полного:'
s 1 "SELECT indexname, pg_size_pretty(pg_relation_size(indexname::text)) size
FROM pg_indexes
WHERE indexname LIKE 'flights_status%';"

c 'А поиск отмененных рейсов будет теперь использовать частичный индекс и станет выполняться быстрее:'
s 1 "EXPLAIN SELECT * 
FROM flights WHERE status = 'Cancelled';"

p
###############################################################################

h 'Индекс по выражению'

c 'Если в условиях используются не столбцы, а, например, обращения к функциям, планировщик не учитывает множество значений. Например, рейсов, совершенных в январе, будет примерно 1/12 от общего количества:'

s 1 "SELECT count(*) FROM flights
WHERE extract(month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow') = 1;"

p

c 'Однако планировщик не понимает смысла функции extract и использует фиксированную селективность 0,5%:'

s 1 "EXPLAIN
SELECT * FROM flights
WHERE extract(month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow') = 1;"

ROWS=`s_bare 1 "SELECT reltuples FROM pg_class WHERE relname = 'flights';"`
s 1 "SELECT $ROWS * 0.005;"

p

c 'Ситуацию можно исправить, построив индекс по выражению, так как для таких выражений собирается собственная статистика.'

s 1 "CREATE INDEX ON flights(
  extract(month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow')
);"
s 1 "ANALYZE flights;"

c 'Теперь оценка исправилась:'

s 1 "EXPLAIN
SELECT * FROM flights
WHERE extract(month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow') = 1;"

p

c 'Статистика для индексов по выражению хранится вместе с базовой статистикой по столбцам таблиц:'

s 1 "SELECT n_distinct, most_common_vals, most_common_freqs
FROM pg_stats
WHERE tablename = 'flights_extract_idx' \gx"

c 'Индекс можно построить только по детерминированному выражению, то есть для одинаковых значений параметров (столбцов) оно всегда должно выдавать одинаковый результат. Подробнее об этом рассказано в теме «Функции».'

###############################################################################
stop_here
cleanup
demo_end
