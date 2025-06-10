#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Список занятых мест'

s 1 "EXPLAIN SELECT f.flight_no, bp.seat_no
FROM flights f
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id;"

c 'Использовано соединение хешированием.'

s 1 "EXPLAIN (analyze, costs off, timing off, summary off)
SELECT f.flight_no, bp.seat_no
FROM flights f
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id;"

c 'Хеш-таблица не поместилась целиком в память, потребовалось два пакета.'

###############################################################################
h '2. Количество занятых мест'

s 1 "EXPLAIN SELECT count(*)
FROM flights f
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id;"

c 'Здесь планировщик использовал параллельный план. В предыдущем запросе это не было оправдано из-за высокой стоимости пересылки данных между процессами, а в данном случае передается только одно число.'

s 1 "EXPLAIN (analyze, costs off, timing off, summary off)
SELECT count(*)
FROM flights f
  JOIN boarding_passes bp ON bp.flight_id = f.flight_id;"

c 'Обратите внимание на поле loops в узлах выше и ниже Gather — оно соответствует реальному числу процессов, работавших над запросом.'

###############################################################################
h '3. Пассажиры и номера рейсов'

s 1 "EXPLAIN (costs off)
SELECT t.passenger_name, f.flight_no
FROM tickets t
  JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no
  JOIN flights f ON f.flight_id = tf.flight_id;"

# Hash Join
#   Hash Cond: (tf.flight_id = f.flight_id)
#   ->  Hash Join
#         Hash Cond: (tf.ticket_no = t.ticket_no)
#         ->  Seq Scan on ticket_flights tf
#         ->  Hash
#               ->  Seq Scan on tickets t
#   ->  Hash
#         ->  Seq Scan on flights f

c 'Сначала выполняется соединение билетов (tickets) с перелетами (ticket_flights), причем хеш-таблица строится по таблице билетов.'
c 'Затем рейсы (flights) соединяются с результатом первого соединения; хеш-таблица строится по таблице рейсов.'

###############################################################################
stop_here
cleanup
demo_end
