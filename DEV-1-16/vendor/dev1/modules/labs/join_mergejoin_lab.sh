#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Параметр cursor_tuple_fraction'

c 'План выполнения курсора:'

s 1 "EXPLAIN DECLARE c CURSOR FOR SELECT * 
FROM aircrafts a
  JOIN seats s ON a.aircraft_code = s.aircraft_code
ORDER BY a.aircraft_code;"

c 'Текущее значение cursor_tuple_fraction:'

s 1 'SHOW cursor_tuple_fraction;'

c 'Уменьшим его:'

s 1 "SET cursor_tuple_fraction = 0.01;"

s 1 "EXPLAIN DECLARE c CURSOR FOR SELECT * 
FROM aircrafts a
  JOIN seats s ON a.aircraft_code = s.aircraft_code
ORDER BY a.aircraft_code;"

c 'Теперь планировщик выбирает другой план: его начальная стоимость ниже (хотя общая стоимость, наоборот, выше).'

###############################################################################
h '2. Полное соединение'

c 'Попробуем выполнить запрос.'

with="WITH cap AS (
    SELECT a.model, count(*)::numeric capacity
    FROM aircrafts a
      JOIN seats s ON a.aircraft_code = s.aircraft_code
   GROUP BY a.model
), a AS (
    SELECT * FROM cap WHERE model LIKE 'Аэробус%'
), b AS (
    SELECT * FROM cap WHERE model LIKE 'Боинг%'
)"
cond="b.capacity::numeric/a.capacity BETWEEN 0.8 AND 1.2"

s 1 "$with
SELECT a.model AS airbus, b.model AS boeing
FROM a FULL JOIN b
  ON $cond
ORDER BY 1,2;"

c 'Получаем ошибку: полное соединение реализовано только для условия равенства, поскольку только вложенный цикл поддерживает соединение по произвольному условию, но зато не поддерживает полное соединение.'
p

c 'Обойти ограничение можно, объединив результаты левого внешнего соединения и антисоединения:'

query="$with
SELECT a.model AS airbus, b.model AS boeing
FROM a LEFT JOIN b
  ON $cond
UNION ALL
SELECT NULL, b.model
FROM b
WHERE NOT EXISTS (
  SELECT 1
  FROM a
  WHERE $cond
)
ORDER BY 1,2;"

s 1 "$query"

c 'План запроса показывает, что соединения выполняются методом вложенного цикла:'

s 1 "EXPLAIN (costs off)
$query"

###############################################################################

stop_here
cleanup
demo_end
