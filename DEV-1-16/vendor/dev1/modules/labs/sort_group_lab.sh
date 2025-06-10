#!/bin/bash

. ../lib
init

start_here

###############################################################################

h '1. Разные способы группировки'

c 'Сначала выполним запрос со значениями параметров по умолчанию:'

s 1 "EXPLAIN
SELECT fare_conditions, count(*)
FROM seats
GROUP BY fare_conditions;"

c 'Для группировки используется узел HashAggregate.'

c 'Запретим группировку хешированием:'

s 1 "SET enable_hashagg = off;"

c 'Повторно выполним запрос и сравним планы выполнения:'

s 1 "EXPLAIN
SELECT fare_conditions, count(*)
FROM seats
GROUP BY fare_conditions;"

c 'Теперь остается только вариант с узлом GroupAggregate, а для него приходится сортировать данные в узле Sort.'

c 'Вернем значение по умолчанию:'

s 1 "RESET enable_hashagg;"

###############################################################################

h '2. Оконные функции и PARTITION BY'

c 'Приведенный запрос возвращает количество элементов в каждой группе:'

s 1 "SELECT status, count(*) OVER (PARTITION BY status)
FROM flights
WHERE flight_no = 'PG0007'
AND departure_airport = 'VKO'
AND flight_id BETWEEN 24104 AND 24115;"

c 'В плане выполнения видно, что группировка обеспечивается тем же узлом WindowAgg, который мы видели при использовании конструкции ORDER BY в определении окна:'

s 1 "EXPLAIN (costs off)
SELECT status, count(*) OVER (PARTITION BY status)
FROM flights
WHERE flight_no = 'PG0007'
AND departure_airport = 'VKO'
AND flight_id BETWEEN 24104 AND 24115;"

c 'Добавим номер текущей строки в ее группе с помощью функции row_number():'

s 1 "SELECT status,
  count(*) OVER (PARTITION BY status),
  row_number() OVER (PARTITION BY status)
FROM flights
WHERE flight_no = 'PG0007'
AND departure_airport = 'VKO'
AND flight_id BETWEEN 24104 AND 24115;"

c 'Добавление новой функции с совпадающим окном не порождает новые узлы в плане:'

s 1 "EXPLAIN (costs off)
SELECT status,
  count(*) OVER (PARTITION BY status),
  row_number() OVER (PARTITION BY status)
FROM flights
WHERE flight_no = 'PG0007'
AND departure_airport = 'VKO'
AND flight_id BETWEEN 24104 AND 24115;"

stop_here
cleanup
demo_end
