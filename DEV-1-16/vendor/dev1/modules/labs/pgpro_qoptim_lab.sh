#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Запрос с соединением слиянием'

s 1  "\c demo"
c 'Получим план запроса с соединением таблиц tickets и ticket_flights.'

s 1 "EXPLAIN (analyze, summary off, timing off, costs off)
SELECT t.ticket_no, t.passenger_name, tf.flight_id, tf.amount
FROM tickets t JOIN ticket_flights tf ON t.ticket_no = tf.ticket_no
ORDER BY t.ticket_no;"
c 'Соединение выполнено слиянием - merge join.'

p

###############################################################################
h '2. Указание выполнить слияние хешированием'

c 'Загрузим динамическую библиотеку pg_hint_plan:'
s 1 "LOAD 'pg_hint_plan';"

c 'Используем указание HashJoin:'
s 1 "EXPLAIN (analyze, summary off, timing off, costs off)
/*+ HashJoin(t tf) */
SELECT t.ticket_no, t.passenger_name, tf.flight_id, tf.amount
FROM tickets t JOIN ticket_flights tf ON t.ticket_no = tf.ticket_no
ORDER BY t.ticket_no;"

p

###############################################################################
h '3. Указание использовать сканирование по битовой карте'

c 'Используем указание BitmapScan:'
s 1 "EXPLAIN (analyze, summary off, timing off, costs off)
/*+ BitmapScan(t) */
SELECT t.ticket_no, t.passenger_name, tf.flight_id, tf.amount
FROM tickets t JOIN ticket_flights tf ON t.ticket_no = tf.ticket_no
ORDER BY t.ticket_no;"

p

###############################################################################
h '4. Запрет использования индекса'

c 'Загрузим динамическую библиотеку plantuner:'
s 1 "LOAD 'plantuner';"

c 'Запретим использовать индекс tickets_pkey:'
s 1 "SET plantuner.disable_index='tickets_pkey';"

c 'Получим план:'
s 1 "EXPLAIN (analyze, summary off, timing off, costs off)
SELECT t.ticket_no, t.passenger_name, tf.flight_id, tf.amount
FROM tickets t JOIN ticket_flights tf ON t.ticket_no = tf.ticket_no
ORDER BY t.ticket_no;"

###############################################################################

stop_here
cleanup
