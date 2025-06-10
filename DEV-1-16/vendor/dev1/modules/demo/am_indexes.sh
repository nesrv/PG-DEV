#!/bin/bash

. ../lib
init

start_here 5

###############################################################################

h 'Хеш-индекс'

c 'Посмотрим на план запроса, получающего список кодов самолетов, в которых есть место с определенным номером:'

s 1 "EXPLAIN (costs off)
SELECT * FROM seats WHERE seat_no = '31D';"

c 'Поскольку подходящего индекса нет, используется последовательное сканирование. Создадим хеш-индекс по полю seat_no и повторим запрос:'

s 1 "CREATE INDEX ON seats USING hash(seat_no);"

s 1 "EXPLAIN (costs off)
SELECT * FROM seats WHERE seat_no = '31D';"

c 'Теперь планировщик использует хеш-индекс и строит битовую карту. Поменяем условие равенства на «больше»:'

s 1 "EXPLAIN (costs off)
SELECT * FROM seats WHERE seat_no > '31D';"

c 'С неравенствами хеш-индекс использоваться не может.'

P 10

###############################################################################

h 'Индекс GiST'

c 'Для демонстрации работы GiST-индекса обратимся к таблице airports_data (на этой таблице построено представление airports). В таблице есть поле coordinates типа point, по нему и будем строить GiST-индекс.'

c 'Но сначала выполним следующий запрос — найдем все аэропорты, находящиеся недалеко от Москвы:'

s 1 "EXPLAIN (costs off)
SELECT airport_code
FROM airports_data
WHERE coordinates <@ '<(37.622513,55.753220),1.0>'::circle;"

c 'Без индекса просматривается вся таблица. Создадим GiST-индекс:'

s 1 "CREATE INDEX airports_gist_idx ON airports_data
USING gist(coordinates);"

c 'Таблица airports_data невелика, поэтому планировщик все равно будет использовать последовательное сканирование. Временно отключим этот метод доступа:'

s 1 "SET enable_seqscan = off;"

c 'Повторим запрос:'

s 1 "EXPLAIN (costs off)
SELECT airport_code
FROM airports_data
WHERE coordinates <@ '<(37.622513,55.753220),1.0>'::circle;"

c 'Теперь планировщик получает нужные строки, обращаясь к индексу airports_gist_idx.'
c 'Удалим созданный индекс:'

s 1 "DROP INDEX airports_gist_idx;"

P 16

###############################################################################

h 'Индекс SP-GiST'

c 'Создадим индекс SP-GiST по полю coordinates в таблице airports_data. Для точек есть два класса операторов. По умолчанию используется point_ops (дерево квадрантов), а мы для примера укажем kd_point_ops (k-мерное дерево):'

s 1 "CREATE INDEX airports_spgist_idx ON airports_data
USING spgist(coordinates kd_point_ops);"

c 'Попробуем найти все аэропорты, расположенные выше (севернее) Надыма:'

s 1 "EXPLAIN (costs off)
SELECT airport_code
FROM airports_data
WHERE coordinates >^ '(72.69889831542969,65.48090362548828)'::point;"

c 'Теперь таблица сканируется по битовой карте, построенной на основе SP-GiST-индекса airports_spgist_idx.'

P 19

###############################################################################

h 'Индекс GIN'

c 'В столбце days_of_week представления routes хранится массив номеров дней недели, по которым выполняется рейс:'

s 1 "SELECT flight_no, days_of_week FROM routes LIMIT 5;"

c 'Для представления нельзя построить индекс, поэтому сохраним его строки в отдельной таблице:'

s 1 "CREATE TABLE routes_tbl
AS SELECT * FROM routes;"

c 'Теперь создадим GIN-индекс:'

s 1 "CREATE INDEX routestbl_gin_idx ON routes_tbl USING gin(days_of_week);"

c 'С помощью GIN-индекса можно, например, отобрать рейсы, отправляющиеся только по средам и субботам:'

s 1 "EXPLAIN (costs off)
SELECT flight_no, departure_airport_name AS departure,
  arrival_airport_name AS arrival, days_of_week
FROM routes_tbl
WHERE days_of_week = ARRAY[3,6];"

c 'Созданный GIN-индекс содержит всего семь элементов: целые числа от 1 до 7, представляющие дни недели. Для каждого из них в индексе хранятся ссылки на рейсы, выполняющиеся в этот день.'

P 22

###############################################################################

h 'Индекс BRIN'

c 'Для примера построим индекс BRIN по самой большой таблице:'

s 1 "CREATE INDEX tflights_brin_idx ON ticket_flights USING brin(flight_id);"

c 'Индексы BRIN дают ощутимый эффект только для очень больших таблиц. Тем не менее, планировщик использует построенный индекс, поскольку по сводной информации (минимум и максимум) можно отсечь зоны, не содержащие требуемых значений:'

s 1 "EXPLAIN (analyze, costs off, timing off)
SELECT *
FROM ticket_flights 
WHERE flight_id BETWEEN 3000 AND 4000;"

c 'Поскольку BRIN не хранит ссылки на версии строк, единственный возможный способ доступа — сканирование по неточной (lossy) битовой карте.'

###############################################################################
stop_here
cleanup
demo_end
