#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Рейсы из Ульяновска'

c 'Индекс на таблице рейсов:'

s 1 "CREATE INDEX ON flights(departure_airport);"

c 'План запроса:'

s 1 "EXPLAIN SELECT *
  FROM flights f JOIN airports a ON a.airport_code = f.departure_airport
  WHERE a.city = 'Ульяновск';"

c 'Планировщик использовал соединение вложенным циклом.'

c 'Заметим, что в данном случае соединение необходимо, так как в Ульяновске два аэропорта:'

s 1 "SELECT airport_code, airport_name FROM airports WHERE city = 'Ульяновск';"

###############################################################################

h '2. Таблица расстояний между аэропортами'

s 1 'CREATE EXTENSION earthdistance CASCADE;'

c 'Чтобы отсечь повторяющиеся пары, можно соединить таблицы по условию «больше»:'

s 1 'EXPLAIN SELECT a1.airport_code "from",
      a2.airport_code "to",
      a1.coordinates <@> a2.coordinates "distance, miles"
  FROM airports a1 JOIN airports a2 ON a1.airport_code > a2.airport_code;'

c 'Вложенный цикл — единственный способ соединения для такого условия.'

###############################################################################
stop_here
cleanup
demo_end
