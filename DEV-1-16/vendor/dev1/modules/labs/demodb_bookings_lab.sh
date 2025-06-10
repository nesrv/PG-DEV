#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Сколько человек в одном бронировании?'

c 'Посчитаем количество человек в каждом бронировании, а затем число бронирований для каждого количества.'

s 1 "SELECT tt.cnt, count(*)
FROM (
  SELECT count(*) cnt
  FROM tickets t 
  GROUP BY t.book_ref
) tt
GROUP BY tt.cnt
ORDER BY tt.cnt;"

###############################################################################
h '2. До каких городов нельзя добраться из Москвы без пересадок?'

c 'Найдем города, куда можно добраться, и выведем все остальные.'

s 1 "SELECT a.city
FROM airports a
EXCEPT
SELECT arr.city
FROM flights f
  JOIN airports dep ON f.departure_airport = dep.airport_code
  JOIN airports arr ON f.arrival_airport = arr.airport_code
WHERE dep.city = 'Москва';"

c 'Интересно, что из Москвы в Москву без пересадок добраться не получится.'

###############################################################################
h '3. Какие модели выполняют больше всего и меньше всего рейсов?'

s 1 "SELECT a.model, f.cnt
FROM aircrafts a
  LEFT JOIN (
    SELECT f.aircraft_code, count(*) cnt
    FROM flights f
    GROUP BY f.aircraft_code
  ) f
  ON f.aircraft_code = a.aircraft_code
ORDER BY cnt DESC NULLS LAST;"

c 'Больше всех трудится маленькая Сессна, а одна модель авиапарка вообще не используется на рейсах.'

###############################################################################
h '4. Какая модель перевезла больше всего пассажиров?'

c 'Число пассажиров на рейсе можно посчитать по посадочным талонам.'

s 1 "SELECT a.model, count(*) cnt
FROM boarding_passes bp
  JOIN flights f ON f.flight_id = bp.flight_id
  JOIN aircrafts a ON a.aircraft_code = f.aircraft_code
GROUP BY a.model
ORDER BY count(*) DESC;"

###############################################################################
stop_here
cleanup
demo_end
