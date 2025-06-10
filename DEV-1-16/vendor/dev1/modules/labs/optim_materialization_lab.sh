#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Отключение узла Materialize'

c 'Проверим план первого запроса из демонстрации:'

s 1 "EXPLAIN SELECT a1.city, a2.city
FROM airports a1, airports a2
WHERE a1.timezone = 'Europe/Moscow'
  AND abs(a2.coordinates[1]) > 66.652;"

c 'Попросим планировщик не использовать материализацию:'

s 1 "SET enable_material = off;"

s 1 "EXPLAIN SELECT a1.city, a2.city
FROM airports a1, airports a2
WHERE a1.timezone = 'Europe/Moscow'
  AND abs(a2.coordinates[1]) > 66.652;"

c 'Планировщик обошелся без материализации, но стоимость плана увеличилась.'

p

c 'Проверим второй запрос:'

s 1 "RESET enable_material;"

s 1 "EXPLAIN (costs off)
SELECT * FROM
  (SELECT * FROM tickets ORDER BY ticket_no) AS t
JOIN
  (SELECT * FROM ticket_flights ORDER BY ticket_no) AS tf 
ON tf.ticket_no = t.ticket_no;"

s 1 "SET enable_material = off;"

s 1 "EXPLAIN (costs off)
SELECT * FROM
  (SELECT * FROM tickets ORDER BY ticket_no) AS t
JOIN
  (SELECT * FROM ticket_flights ORDER BY ticket_no) AS tf 
ON tf.ticket_no = t.ticket_no;"

c 'В данном случае планировщик не может не использовать материализацию, поскольку для соединения слиянием требуется не только перемещаться по набору данных вперед, но и возвращаться назад.'

s 1 "RESET enable_material;"

###############################################################################
h '2. Параметр from_collapse_limit'

c 'Сначала посмотрим, как работает запрос со значением from_collapse_limit по умолчанию:'

s 1 "SHOW from_collapse_limit;"

s 1 "EXPLAIN (costs off, summary off, settings)
SELECT *
FROM
  (
    SELECT *
    FROM ticket_flights tf, tickets t
    WHERE tf.ticket_no = t.ticket_no
  ) ttf,
  flights f
WHERE f.flight_id = ttf.flight_id;"

c 'В подзапросе соединяются две таблицы, но оптимизатор раскрывает подзапрос и выбирает порядок соединения для всех трех таблиц. Первыми здесь соединяются таблицы перелетов (ticket_flights) и рейсов (flights).'
c 'Теперь уменьшим значение from_collapse_limit до единицы и посмотрим на новый план того же запроса:'

s 1 "SET from_collapse_limit = 1;"

s 1 "EXPLAIN (costs off, summary off, settings)
SELECT *
FROM
  (
    SELECT *
    FROM ticket_flights tf, tickets t
    WHERE tf.ticket_no = t.ticket_no
  ) ttf,
  flights f
WHERE f.flight_id = ttf.flight_id;"

c 'План запроса поменялся — сначала соединяются две таблицы из подзапроса, который теперь не раскрывается.'

c 'Если во FROM вместо списка таблиц использовать конструкцию JOIN, оптимизатор сначала преобразует каждую такую конструкцию в список таблиц (при этом обрабатывая таблицы группами не более чем по join_collapse_limit), а потом уже раскрывает подзапросы (на глубину не более чем from_collapse_limit). Поэтому имеет смысл устанавливать обоим параметрам равные значения.'

###############################################################################
stop_here
cleanup
demo_end
