#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Индексы'

s 1 '\c demo'
c 'Чтобы у планировщика PostgreSQL было больше вариантов соединения таблиц, создадим два индекса.'
s 1 "CREATE INDEX ON flights (scheduled_departure);"
s 1 "CREATE INDEX ON ticket_flights (fare_conditions);"

###############################################################################
h '2. Запрос с обычным планированием'

c 'Отключим параллельную обработку и увеличим work_mem, чтобы вся работа происходила в оперативной памяти.'
s 1 "ALTER SYSTEM SET max_parallel_workers_per_gather = 0;"
s 1 "ALTER SYSTEM SET work_mem = '256MB';"
s 1 "SELECT pg_reload_conf();"

# Запрос
QUERY=$(
cat <<'SQL'
EXPLAIN (analyze, buffers, timing off)
SELECT t.ticket_no
FROM flights f
  JOIN ticket_flights tf ON f.flight_id = tf.flight_id
  JOIN tickets t ON tf.ticket_no = t.ticket_no
WHERE f.scheduled_departure > '2016-08-01'::timestamptz
  AND f.actual_arrival < f.scheduled_arrival + interval '1 hour'
  AND tf.fare_conditions = 'Business'
SQL
)

c 'Получим количество пассажиров, которые летели бизнес-классом начиная с 01.08.2016 и прибыли с опозданием не более часа.'
s 1 "$QUERY;"
c 'Имеется несоответствие по количествам планируемых и реально полученных строк.'

p

###############################################################################
h '3. AQO'

c 'Чтобы работал AQO, нужно загрузить библиотеку.'
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'aqo';"
psql_close 1
pgctl_restart A

c 'Подключим расширение.'
psql_open A 1 demo
s 1 'CREATE EXTENSION aqo;'

c 'Режим по умолчанию — controlled.'
s 1 "SHOW aqo.mode;"

c 'Сбросим предыдущую статистику AQO и включим режим learn.'
s 1 "SELECT aqo_reset();"
s 1 "SET aqo.mode = 'learn';"
s 1 "SET aqo.show_hash = on;"
s 1 "SET aqo.show_details = on;"

c 'Будем собирать статистику для всех соединений.'
s 1 "SET aqo.join_threshold = 1;"

c 'Выполним запрос и исследуем его план.'
s 1 "$QUERY;"
c 'AQO не оптимизирует запрос, если встречает его впервые.'
p

c 'Повторим запрос.'
s 1 "$QUERY;"
c 'Теперь количества планируемых и реально полученных строк стали одинаковыми.'

###############################################################################

stop_here
cleanup
