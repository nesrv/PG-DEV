#!/bin/bash

. ../lib
init

start_here 5

###############################################################################

h 'Узел Materialize'

c 'Если операция требует существенных ресурсов, а к ее результату обращаются многократно, планировщик может выбрать план с узлом Materialize, в котором полученные строки накапливаются для повторного использования:'

s 1 "EXPLAIN (costs off)
SELECT a1.city, a2.city
FROM airports a1, airports a2
WHERE a1.timezone = 'Europe/Moscow'
  AND abs(a2.coordinates[1]) > 66.652; -- за полярным кругом
"
c 'Здесь для предиката внутреннего набора строк нет подходящего индекса, поэтому план с материализацией оказывается выгодным.'

p

c 'В некоторых случаях планировщик использует материализацию внутреннего набора данных и при соединении слиянием, чтобы иметь возможность перечитать часть строк при повторяющихся значениях во внешнем наборе:'

s 1 "EXPLAIN (costs off)
SELECT * FROM
  (SELECT * FROM tickets ORDER BY ticket_no) AS t
JOIN
  (SELECT * FROM ticket_flights ORDER BY ticket_no) AS tf 
ON tf.ticket_no = t.ticket_no;"

P 7

###############################################################################

h 'Материализация CTE'

c 'Оптимизатор старается не материализовать подзапросы в WITH без надобности:'

s 1 "EXPLAIN (costs off)
WITH q AS (
  SELECT f.flight_id, a.aircraft_code
  FROM flights f
    JOIN aircrafts a ON a.aircraft_code = f.aircraft_code
)
SELECT *
FROM q
  JOIN seats s ON s.aircraft_code = q.aircraft_code
WHERE s.seat_no = '1A';"

c 'Но явное указание заставляет оптимизатор планировать подзапрос отдельно от основного запроса:'

s 1 "EXPLAIN (costs off)
WITH q AS MATERIALIZED (
  SELECT f.flight_id, a.aircraft_code
  FROM flights f
    JOIN aircrafts a ON a.aircraft_code = f.aircraft_code
)
SELECT *
FROM q
  JOIN seats s ON s.aircraft_code = q.aircraft_code
WHERE s.seat_no = '1A';"

p

c 'Если подзапрос используется в запросе несколько раз, планировщик выбирает материализацию, чтобы не выполнять одни и те же действия многократно:'

s 1 "EXPLAIN (analyze, costs off, buffers)
WITH b AS (
  SELECT * FROM bookings
)
SELECT *
FROM b AS b1
  JOIN b AS b2 ON b1.book_ref = b2.book_ref
WHERE b2.book_ref = '000112';"

c 'Обычно это оправдано, особенно если в подзапросе происходят затратные вычисления. Но в некоторых случаях (как в этом примере) план без материализации может оказаться эффективнее, и тогда ее можно отменить. Сравните значение buffers с предыдущим вариантом:'

s 1 "EXPLAIN (analyze, costs off, buffers)
WITH b AS NOT MATERIALIZED (
  SELECT * FROM bookings
)
SELECT *
FROM b AS b1
  JOIN b AS b2 ON b1.book_ref = b2.book_ref
WHERE b2.book_ref = '000112';"

c 'Однако если подзапрос изменяет данные, материализация будет выполнена в любом случае: изменение обязано произойти только один раз.'

P 9

###############################################################################

h 'Рекурсивные запросы'

c 'Убедимся в том, что рекурсивный запрос материализует промежуточные данные. Для этого намеренно напишем его так, чтобы рабочая и промежуточная таблицы не поместились в память:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
WITH RECURSIVE r(n, airport_code) AS (
  SELECT 1, a.airport_code
  FROM airports a
  UNION ALL
  SELECT r.n+1, f.arrival_airport
  FROM r
    JOIN flights f ON f.departure_airport = r.airport_code
  WHERE r.n < 2
)
SELECT * FROM r;
"

c 'Обратите внимание на строки temp read/written в узлах WorkTable Scan и Recursive Union, специфичных для рекурсивных запросов.'

P 12

###############################################################################

h 'Временные таблицы'

c 'Создадим временную таблицу:'

s 1 "CREATE TEMP TABLE airports_msk
ON COMMIT PRESERVE ROWS -- по умолчанию
AS SELECT *
FROM airports
WHERE timezone = 'Europe/Moscow';"

c 'Временная таблица создается во временной схеме pg_temp.'

c 'По умолчанию таблица существует до конца сеанса; можно указать, чтобы при завершении транзакции удалялись строки (ON COMMIT DELETE ROWS) или сама таблица (ON COMMIT DROP).'

p

c 'Зачастую есть смысл проанализировать только что заполненную временную таблицу, прежде чем использовать ее в запросах. Сравните оценки кардинальности при выборе из обычной таблицы и из временной:'

s 1 "EXPLAIN
SELECT *
FROM airports
WHERE timezone = 'Europe/Moscow';"

s 1 "EXPLAIN
SELECT *
FROM airports_msk;"

c 'В последнем случае оптимизатор, не имея статистики, предполагает, что таблица занимает 10 страниц, на которых умещается 520 строк, и стоимость получается завышенной:'

s 1 "SELECT relpages, reltuples,
   10 * current_setting('seq_page_cost')::float +
  520 * current_setting('cpu_tuple_cost')::float AS cost
FROM pg_class
WHERE relname = 'airports_msk'
  AND relpersistence = 't'; -- временная"

c 'Если проанализировать таблицу, оценка станет точной:'

s 1 "ANALYZE airports_msk;"

s 1 "EXPLAIN
SELECT *
FROM airports_msk;"

P 14

###############################################################################

h 'Управление порядком соединений'

# TODO В 17 появился EXPLAIN (memory) - можно будет показать расход памяти при разном
#      количестве таблиц.

c 'Значение по умолчанию параметра join_collapse_limit выбрано так, чтобы планирование соединения такого количества таблиц не требовало чрезмерных ресурсов:'

s 1 "SHOW join_collapse_limit;"

c 'Выполним запрос, в котором используется явное соединение таблиц с помощью ключевого слова JOIN:'

s 1 "EXPLAIN (costs on)
SELECT *
FROM tickets t
 JOIN ticket_flights tf ON (tf.ticket_no = t.ticket_no)
 JOIN flights f ON (f.flight_id = tf.flight_id);"

c 'В выбранном плане сначала соединяются таблицы рейсов (flights) и перелетов (ticket_flights), а затем результат соединяется с билетами (tickets).'

p

c 'Установив параметр join_collapse_limit в единицу, можно зафиксировать порядок соединений:'

s 1 "SET join_collapse_limit = 1;"

s 1 "EXPLAIN (costs on)
SELECT *
FROM tickets t
 JOIN ticket_flights tf ON (tf.ticket_no = t.ticket_no)
 JOIN flights f ON (f.flight_id = tf.flight_id);"

c 'Теперь таблицы соединяются друг с другом в том порядке, в котором они перечислены в запросе, несмотря на то, что итоговая стоимость запроса выше.'
c 'Однако такой способ перекладывает на автора запроса слишком много ответственности. Планировщик сможет выбирать только то, какой из наборов строк поставить в соединении внешним, а какой — внутренним.'

s 1 "RESET join_collapse_limit;"

c 'С похожим параметром from_collapse_limit предлагается познакомиться в практике.'

P 16

###############################################################################

h 'Материализованные представления'

c 'Создадим материализованное представление:'

s 1 "CREATE MATERIALIZED VIEW airports_msk AS
SELECT *
FROM airports
WHERE timezone = 'Europe/Moscow';"

s 1 "\dt airports_msk"

c 'Схема pg_temp при поиске проверяется первой, теперь придется обращаться к материализованному представлению по полному имени. Это неудобно, лучше удалить временную таблицу:'

s 1 "DROP TABLE pg_temp.airports_msk;"

c 'Материализованные представления можно индексировать:'

s 1 "CREATE UNIQUE INDEX ON airports_msk (airport_code);"
s 1 "EXPLAIN (costs off) SELECT * 
FROM airports_msk 
ORDER BY airport_code
LIMIT 3;"

c 'При анализе и автоанализе для материализованных представлений собирается та же статистика, что и для таблиц.'

c 'При изменении содержимого базовых таблиц строки материализованного представления не изменяются:'

s 1 "INSERT INTO airports_data (airport_code, airport_name, city, coordinates, timezone)
  VALUES ('ZIA', '{\"ru\": \"Жуковский\"}', '{}', point(38.1517, 55.5533), 'Europe/Moscow');"
s 1 "SELECT count(*)
FROM airports_msk
WHERE airport_code = 'ZIA';"

c 'Синхронизацию нужно проводить явно. Команда REFRESH полностью блокирует материализованное представление на время перестроения, что может быть нежелательным. В данном случае этого можно избежать, указав CONCURRENTLY, поскольку на материализованном представлении создан уникальный индекс:'

s 1 "REFRESH MATERIALIZED VIEW CONCURRENTLY airports_msk;"
s 1 "SELECT count(*)
FROM airports_msk
WHERE airport_code = 'ZIA';"

###############################################################################
stop_here
cleanup
