#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Оптимизация короткого запроса'

c 'Отключим параллельное выполнение.' 

s 1 "SET max_parallel_workers_per_gather = 0;"

s 1 "EXPLAIN (analyze, timing off)
SELECT t.*
FROM tickets t
  JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no
  JOIN flights f ON f.flight_id = tf.flight_id
WHERE tf.fare_conditions = 'Business'
  AND f.actual_departure > f.scheduled_departure + interval '5 hour';"

c 'Здесь мы имеем дело с запросом, характерным для OLTP — небольшое число строк, для получения которых надо выбрать только небольшую часть данных. Поэтому общее направление оптимизации — переход от полного сканирования и соединения хешированием к индексам и вложенным циклам.'

c 'Заметим, что рейс, задержанный более чем на 5 часов, всего один, а планировщик сканирует всю таблицу. Можно построить индекс по выражению на разности двух столбцов и немного переписать условие:'

s 1 "CREATE INDEX ON flights ((actual_departure - scheduled_departure));"
s 1 "ANALYZE flights;"

s 1 "EXPLAIN (analyze, timing off)
SELECT t.*
FROM tickets t
  JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no
  JOIN flights f ON f.flight_id = tf.flight_id
WHERE tf.fare_conditions = 'Business'
  AND f.actual_departure - f.scheduled_departure > interval '5 hour';"

c 'Теперь займемся таблицей ticket_flights, которая тоже сканируется полностью, хотя из нее читается незначительная часть строк.'
c 'Помог бы индекс по классам обслуживания fare_conditions, но лучше создать индекс по столбцу flight_id, что позволит эффективно выполнять соединение вложенным циклом с flights:'

s 1 "CREATE INDEX ON ticket_flights(flight_id);"

s 1 "EXPLAIN (analyze, timing off)
SELECT t.*
FROM tickets t
  JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no
  JOIN flights f ON f.flight_id = tf.flight_id
WHERE tf.fare_conditions = 'Business'
  AND f.actual_departure - f.scheduled_departure > interval '5 hour';"

c 'Время выполнения уменьшилось до миллисекунд.'

###############################################################################
h '2. Оптимизация длинного запроса'

c 'Очевидно, мы имеем дело с длинным запросом: в нем присутствует большая таблица перелетов ticket_flights, при этом ни на одну таблицу не накладывается никаких условий. Выполним запрос и посмотрим на план его выполнения:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT a.aircraft_code, (
  SELECT round(avg(tf.amount))
  FROM flights f 
    JOIN ticket_flights tf ON tf.flight_id = f.flight_id 
  WHERE f.aircraft_code = a.aircraft_code 
) 
FROM aircrafts a;"

c 'В плане запроса видим, что оценки кардинальности вполне адекватны во всех узлах, большие таблицы сканируются последовательно и применяется хеш-соединение.'
c 'Однако при этом запрос читает в несколько раз больше страниц, чем необходимо:'

s 1 "SELECT sum(relpages) FROM pg_class
WHERE relname IN ('flights','ticket_flights','aircrafts_ml');"

c 'Причина в коррелированном подзапросе, который выполняется для каждой из девяти моделей самолетов, образуя неявный вложенный цикл. Раскроем подзапрос, добавив группировку.'
c 'Может показаться заманчивым избавиться от таблицы самолетов aircrafts, ведь код самолета можно получить непосредственно из таблицы рейсов flights. Однако в этом случае из результатов пропадет модель, не совершившая ни одного рейса. Поэтому необходимо левое соединение.'
c 'Кроме того, сразу вспомним, что в демонстрации мы увеличивали work_mem, чтобы избежать двухпроходного соединения.'

s 1 "SET work_mem = '8MB';"

s 1 "EXPLAIN (analyze, buffers, timing off)
SELECT a.aircraft_code, round(avg(tf.amount))
FROM aircrafts a 
  LEFT JOIN flights f ON f.aircraft_code = a.aircraft_code 
  LEFT JOIN ticket_flights tf ON tf.flight_id = f.flight_id 
GROUP BY a.aircraft_code;"

c 'Лишние чтения пропали, запрос ускорился.'

###############################################################################
stop_here
cleanup
demo_end
