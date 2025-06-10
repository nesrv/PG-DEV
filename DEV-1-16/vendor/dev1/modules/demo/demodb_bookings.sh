#!/bin/bash

. ../lib
init

start_here 6

###############################################################################

h 'Бронирование'

c 'Начнем с бронирования и выберем какое-нибудь одно:'

s 1 "SELECT * FROM bookings b WHERE b.book_ref = '0824C5';"

c 'Мы видим дату бронирования и общую сумму.'
c 'Если сравнивать дату с текущей, то бронирование сделано довольно давно:'

s 1 "SELECT now();"

c 'Но для демобазы «текущим» моментом является другая дата:'

s 1 "SELECT bookings.now();"

c 'Так что «на самом деле» билеты забронированы 20 дней назад:'

s 1 "SELECT bookings.now() - b.book_date
FROM bookings b
WHERE b.book_ref = '0824C5';"

P 8

###############################################################################
h 'Билеты'

c 'Посмотрим, какие билеты включены в выбранное бронирование:'

s 1 "SELECT t.*
FROM bookings b
  JOIN tickets t ON t.book_ref = b.book_ref
WHERE b.book_ref = '0824C5';"

c 'Летят два человека; на каждого оформляется собственный билет с информацией о пассажире.'

P 10

###############################################################################

h 'Перелеты'

c 'По какому маршруту летят пассажиры? Добавим в запрос перелеты.'

s 1 "SELECT tf.*
FROM tickets t
  JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no
WHERE t.ticket_no = '0005435126781';"

c 'Здесь мы смотрим только на один билет — все маршруты в одном бронировании всегда совпадают.'
c 'Видим, что в билете 6 перелетов; из них один бизнес-классом, другие — экономом.'

P 12

###############################################################################

h 'Рейсы'

c 'Теперь разберемся, какие рейсы скрываются за выбранными перелетами.'

s 1 "SELECT f.flight_id, f.scheduled_departure,
  f.departure_airport dep, f.arrival_airport arr,
  f.status, f.aircraft_code aircraft
FROM tickets t
  JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no
  JOIN flights f ON f.flight_id = tf.flight_id
WHERE t.ticket_no = '0005435126781'
ORDER BY f.scheduled_departure;"

c 'Видим три рейса «туда» и три «обратно». «Туда» все рейсы уже совершены (Arrived), а в настоящее время пассажир летит «обратно» (Departed). Следующий рейс будет по расписанию (On Time), а на последний еще не открыта регистрация (Scheduled).'

p

c 'Посмотрим внимательнее на все столбцы одного из рейсов.'

s 1 "SELECT * FROM flights f WHERE f.flight_id = 22566 \gx"

c 'Реальное время может отличаться от времени по расписанию (обычно не сильно).'

p

c 'Номер flight_no одинаков для всех рейсов, следующих по одному маршруту по расписанию:'

s 1 "SELECT f.flight_id, f.flight_no, f.scheduled_departure
FROM flights f
WHERE f.flight_no = 'PG0412'
ORDER BY f.scheduled_departure
LIMIT 10;"

P 14

###############################################################################

h 'Аэропорты'

c 'В качестве ключа для аэропортов используется общепринятый трехбуквенный код. Посмотрим полную информацию об одном аэропорте:'

s 1 "SELECT * FROM airports WHERE airport_code = 'VKO' \gx"

c 'Помимо названия и города, хранятся координаты аэропорта и часовой пояс.'
c 'Теперь мы можем расшифровать сведения о рейсах:'

s 1 "SELECT f.scheduled_departure,
  dep.airport_code || ' ' || dep.city || ' (' || dep.airport_name || ')' departure,
  arr.airport_code || ' ' || arr.city || ' (' || arr.airport_name || ')' arrival
FROM tickets t
  JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no
  JOIN flights f ON f.flight_id = tf.flight_id
  JOIN airports dep ON dep.airport_code = f.departure_airport
  JOIN airports arr ON arr.airport_code = f.arrival_airport
WHERE t.ticket_no = '0005435126781'
ORDER BY f.scheduled_departure;"

c 'Чтобы не выписывать каждый раз подобный запрос, существует представление flights_v:'

s 1 "SELECT * FROM flights_v f WHERE f.flight_id = 22566 \gx"

c 'Здесь видим и местное время в часовых поясах городов отправления и прибытия, длительность полета, названия аэропортов.'

c 'Поскольку в демобазе маршруты не меняются со временем, из таблицы рейсов можно выделить информацию, которая не зависит от конкретной даты вылета. Такая информация собрана в представлении routes:'

s 1 "SELECT * FROM routes r WHERE r.flight_no = 'PG0412' \gx"

c 'Видно, что рейсы выполняются ежедневно (массив days_of_week).'

P 16

###############################################################################

h 'Самолеты'

c 'Модели самолетов, обслуживающих рейсы, также используют стандартные трехсимвольные коды в качестве первичных ключей.'

s 1 "SELECT a.*
FROM flights f
  JOIN aircrafts a ON a.aircraft_code = f.aircraft_code
WHERE f.flight_id = 22566;"

P 18

###############################################################################

h 'Места'

c 'В демобазе все самолеты одной модели имеют одинаковую конфигурацию салона. Посмотрим на первый ряд:'

s 1 "SELECT s.*
FROM flights f
  JOIN aircrafts a ON a.aircraft_code = f.aircraft_code
  JOIN seats s ON s.aircraft_code = a.aircraft_code
WHERE f.flight_id = 22566 
AND s.seat_no ~ '^1.$';"

c 'Это бизнес-класс.'

c 'А вот общее число мест различных классов обслуживания:'

s 1 "SELECT s.fare_conditions, count(*)
FROM seats s
WHERE s.aircraft_code = '733'
GROUP BY s.fare_conditions;"

P 20

###############################################################################

h 'Посадочные талоны'

c 'На каких местах сидел наш пассажир? Для этого надо заглянуть в посадочный талон, который выдается при регистрации на рейс:'

s 1 "SELECT f.status, bp.*
FROM tickets t
  JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no 
  JOIN flights f ON f.flight_id = tf.flight_id
  LEFT JOIN boarding_passes bp
    ON bp.ticket_no = tf.ticket_no AND bp.flight_id = tf.flight_id
WHERE t.ticket_no = '0005435126781'
ORDER BY f.scheduled_departure;"

c 'На два оставшихся рейса пассажир еще не зарегистрировался.'

P 22

###############################################################################

h 'Многоязычность'

c 'В демобазе заложена возможность перевода названий аэропортов, городов и самолетов на другие языки. Как мы видели, по умолчанию все названия выводятся по-русски:'

s 1 "SELECT * FROM airports a WHERE a.airport_code = 'VKO' \gx"

c 'Чтобы сменить язык, достаточно установить конфигурационный параметр:'

s 1 "SET bookings.lang = 'en';"
s 1 "SELECT * FROM airports a WHERE a.airport_code = 'VKO' \gx"

c 'Реализация использует представление над базовой таблицей, которая содержит переводы в формате JSON:'

s 1 "SELECT * FROM airports_data ml WHERE ml.airport_code = 'VKO' \gx"

###############################################################################
stop_here
cleanup
demo_end
