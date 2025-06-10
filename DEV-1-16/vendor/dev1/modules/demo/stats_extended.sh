#!/bin/bash

. ../lib
init

start_here 5

###############################################################################

h 'Функциональные зависимости'

c 'Рассмотрим запрос с двумя условиями:'

s 1 "SELECT count(*)
FROM flights
WHERE flight_no = 'PG0007' AND departure_airport = 'VKO';"

p

c 'Оценка оказывается сильно заниженной:'

s 1 "EXPLAIN
SELECT * FROM flights 
WHERE flight_no = 'PG0007' AND departure_airport = 'VKO';"

c 'Причина в том, что планировщик полагается на независимость предикатов и считает итоговую селективность как произведение селективностей предикатов. Это хорошо видно в приведенном плане: оценка в узле Bitmap Index Scan (условие на flight_no) верная, а после фильтрации в узле Bitmap Heap Scan (условие на departure_airport) — заниженная.'

p

c 'Однако мы понимаем, что номер рейса однозначно определяет аэропорт отправления: фактически, второе условие избыточно (конечно, считая, что аэропорт указан правильно).'
c 'Это можно объяснить планировщику с помощью статистики по функциональной зависимости:'

s 1 "CREATE STATISTICS (dependencies)
ON flight_no, departure_airport FROM flights;"
s 1 "ANALYZE flights;"

c 'Собранная статистика хранится в следующем виде:'

s 1 "SELECT dependencies
FROM pg_stats_ext
WHERE statistics_name = 'flights_flight_no_departure_airport_stat';"

c 'Сначала идут порядковые номера атрибутов, а после двоеточия — коэффициент зависимости.'

s 1 "EXPLAIN
SELECT * FROM flights
WHERE flight_no = 'PG0007' AND departure_airport = 'VKO';"

c 'Теперь оценка улучшилась.'

c 'Команда \d показывает объекты расширенной статистики для конкретной таблицы:'

s 1 "\d flights"

c 'В разделе Statistics objects показаны имена, столбцы и нестандартные целевые значения объектов статистики.'

P 7

###############################################################################

h 'Частые комбинации'

c 'Столбцы могут быть коррелированы, но не всегда между ними есть прямая функциональная зависимость. Выполним такой запрос:'

s 1 "EXPLAIN (analyze, timing off, summary off)
SELECT * FROM flights
WHERE departure_airport = 'LED' AND aircraft_code = '321';"

c 'Планировщик ошибается в несколько раз. Учет функциональной зависимости недостаточно исправит ситуацию:'

s 1 "CREATE STATISTICS (dependencies)
ON departure_airport, aircraft_code FROM flights;"
s 1 "ANALYZE flights;"
s 1 "EXPLAIN
SELECT * FROM flights
WHERE departure_airport = 'LED' AND aircraft_code = '321';"

p

c 'В этом случае можно добавить расширенную статистику по частым комбинациям значений нескольких столбцов:'

s 1 "DROP STATISTICS flights_departure_airport_aircraft_code_stat;"
s 1 "CREATE STATISTICS (mcv)
ON departure_airport, aircraft_code FROM flights;"
s 1 'ANALYZE flights;'

s 1 "EXPLAIN
SELECT * FROM flights
WHERE departure_airport = 'LED' AND aircraft_code = '321';"

c 'Теперь оценка улучшилась.'

p

c 'Количество собираемых наиболее частых значений определяется параметром default_statistics_target. Его можно задать для конкретной статистики:'

s 1 "ALTER STATISTICS flights_departure_airport_aircraft_code_stat 
SET STATISTICS 300;"
s 1 'ANALYZE flights;'
s 1 "EXPLAIN (analyze, timing off, summary off)
SELECT * FROM flights
WHERE departure_airport = 'LED' AND aircraft_code = '321';"

c 'Оценка кардинальности еще немного улучшилась.'
c 'Однако это не привело к дальнейшему улучшению плана, поэтому увеличение ориентира статистики в данном случае вряд ли оправдано.'

p

c 'Статистику по наиболее частым комбинациям можно посмотреть так:'

s 1 "SELECT values, frequency
FROM pg_statistic_ext
  JOIN pg_statistic_ext_data ON oid = stxoid,
  pg_mcv_list_items(stxdmcv) m
WHERE stxname = 'flights_departure_airport_aircraft_code_stat'
LIMIT 10;"

P 9

###############################################################################

h 'Уникальные комбинации'

c 'Другая ситуация, в которой планировщик ошибается с оценкой, связана с группировкой. Количество пар аэропортов, связанных прямыми рейсами, ограничено:'

s 1 "SELECT count(*) FROM (
  SELECT DISTINCT departure_airport, arrival_airport FROM flights
) t;"

c 'Но планировщик не знает об этом:'

s 1 "EXPLAIN
SELECT DISTINCT departure_airport, arrival_airport FROM flights;"

p

c 'Расширенная статистика позволяет исправить и эту оценку (если не указать вид статистики, в создаваемый объект будут включены все поддерживаемые виды):'

s 1 "CREATE STATISTICS
ON departure_airport, arrival_airport FROM flights;"
s 1 "ANALYZE flights;"

s 1 "EXPLAIN
SELECT DISTINCT departure_airport, arrival_airport FROM flights;"

p

c 'Статистику по уникальным комбинациям можно увидеть так:'

s 1 "SELECT n_distinct
FROM pg_stats_ext
WHERE statistics_name = 'flights_departure_airport_arrival_airport_stat';"

c 'Посмотреть список всех объектов расширенной статистики можно командой \dX:'
s 1 "\x \dX \x"

c 'Отображается наличие статистики по типам (Ndistinct, Dependencies, MCV), а значения нужно смотреть в таблице pg_statistic_ext_data.'

P 11

###############################################################################

h 'Статистика по выражению'

c 'Как мы видели в теме «Базовая статистика», если в условии используются выражение, планировщик, не имея информации о селективности, использует константу и часто ошибается:'

s 1 "SELECT count(*) FROM flights
WHERE extract(month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow') = 1;"

s 1 "EXPLAIN
SELECT * FROM flights
WHERE extract(month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow') = 1;"

p

c 'В теме «Базовая статистика» мы исправляли ситуацию, построив индекс по выражению, но это возможно не во всех случаях. К тому же индексы требуют ресурсов для хранения и постоянной синхронизации. Можно поступить иначе — добавить расширенную статистику по выражению:'

s 1 "CREATE STATISTICS 
ON extract(month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow')
FROM flights;"

s 1 "ANALYZE flights;"

s 1 "EXPLAIN
SELECT * FROM flights
WHERE extract(month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow') = 1;"

c 'Оценка стала корректной.'

p

c 'Расширенная статистика по выражениям хранится отдельно. Вот несколько столбцов:'

s 1 "SELECT statistics_name, expr, n_distinct, most_common_vals
FROM pg_stats_ext_exprs \gx"

###############################################################################
stop_here
cleanup
demo_end
