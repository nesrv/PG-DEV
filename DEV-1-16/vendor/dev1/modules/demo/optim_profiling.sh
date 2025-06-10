#!/bin/bash

. ../lib
init

start_here 10

###############################################################################
h 'Расширение pg_stat_statements'

c 'Подключим расширение pg_stat_statements, с помощью которого будем строить профиль:'

s 1 "CREATE EXTENSION pg_stat_statements;"
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';"

c 'Подключение библиотеки требует перезагрузки.'

pgctl_restart A
psql_open A 1 demo

c 'Настроим расширение так, чтобы собиралась информация о всех запросах, в том числе вложенных:'

s 1 "SET pg_stat_statements.track = 'all';"

c 'Создадим представление, чтобы смотреть на собранную статистику выполнения операторов:'

s 1 "CREATE VIEW statements_v AS
SELECT
  queryid,
  toplevel,
  substring(regexp_replace(query,' +',' ','g') FOR 55) AS query,
  calls,
  round(total_exec_time)/1000 AS time_sec,
  shared_blks_hit + shared_blks_read + shared_blks_written AS shared_blks
FROM pg_stat_statements
ORDER BY total_exec_time DESC;"

c 'Здесь мы для простоты показываем только часть полей и выводим только общее число страниц кеша.'

p

###############################################################################

h 'Профиль выполнения'

c 'Рассмотрим задачу. Требуется построить отчет, выводящий сводную таблицу количества перевезенных пассажиров: строками отчета должны быть модели самолетов, а столбцами — категории обслуживания.'

c 'Сначала создадим функцию, возвращающую число пассажиров для заданной модели и категории обслуживания:'

s 1 "CREATE FUNCTION qty(aircraft_code char, fare_conditions varchar)
RETURNS bigint AS \$\$
  SELECT count(*)
  FROM flights f 
    JOIN boarding_passes bp ON bp.flight_id = f.flight_id 
    JOIN seats s ON s.aircraft_code = f.aircraft_code AND s.seat_no = bp.seat_no 
  WHERE f.aircraft_code = qty.aircraft_code AND s.fare_conditions = qty.fare_conditions;
\$\$ STABLE LANGUAGE sql;"

c 'Для отчета создадим функцию, возвращающую набор строк:'

s 1 "CREATE FUNCTION report()
RETURNS TABLE(model text, economy bigint, comfort bigint, business bigint)
AS \$\$
DECLARE
  r record;
BEGIN 
  FOR r IN SELECT a.aircraft_code, a.model FROM aircrafts a ORDER BY a.model LOOP
    report.model := r.model;
    report.economy := qty(r.aircraft_code, 'Economy');
    report.comfort := qty(r.aircraft_code, 'Comfort');
    report.business := qty(r.aircraft_code, 'Business');
    RETURN NEXT;
  END LOOP;
END;
\$\$ STABLE LANGUAGE plpgsql;"

c 'Теперь исследуем работу предложенной реализации. Сбросим статистику:'

s 1 "SELECT pg_stat_statements_reset();"

c 'Дата последнего сброса статистики видна в представлении pg_stat_statements_info:'

s 1 "SELECT stats_reset FROM pg_stat_statements_info;"

c 'Выполним функцию report():'

s 1 "SELECT * FROM report();"

p

c 'Посмотрим, какую статистику мы получили:'

s 1 "SELECT * FROM statements_v \gx"

ul 'Первым идет основной запрос, который детализируется ниже. Toplevel — признак выполнения запроса на верхнем уровне.'
ul 'Вторым идет запрос из функции qty — он вызывался 27 раз.'
ul 'Третий — запрос, по которому работает цикл.'

p

c 'Обратите внимание, что идентификатор запроса в pg_stat_statements совпадает с системным благодаря настройке compute_query_id:'

s 1 "EXPLAIN (verbose)
SELECT pg_stat_statements_reset();"

P 12

###############################################################################

h 'Профиль одного запроса'

c 'Попробуем теперь вывести тот же отчет одним запросом и посмотрим на его выполнение командой EXPLAIN с параметрами analyze и buffers, чтобы в плане отображалось количество фактически прочитанных и записанных страниц файлов данных и временных файлов:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
WITH t AS (
  SELECT f.aircraft_code, 
    count(*) FILTER (WHERE s.fare_conditions = 'Economy') economy,
    count(*) FILTER (WHERE s.fare_conditions = 'Comfort') comfort,
    count(*) FILTER (WHERE s.fare_conditions = 'Business') business 
  FROM flights f 
    JOIN boarding_passes bp ON bp.flight_id = f.flight_id 
    JOIN seats s ON s.aircraft_code = f.aircraft_code AND s.seat_no = bp.seat_no 
  GROUP BY f.aircraft_code
)
SELECT a.model,
  coalesce(t.economy,0) economy, 
  coalesce(t.comfort,0) comfort, 
  coalesce(t.business,0) business 
FROM aircrafts a
  LEFT JOIN t ON a.aircraft_code = t.aircraft_code 
ORDER BY a.model;"

c 'Обратите внимание, как уменьшилось время выполнения запроса и насколько меньше страниц пришлось прочитать благодаря устранению избыточных чтений (верхняя строчка Buffers).'

p

c 'Можно посчитать общее количество страниц во всех задействованных таблицах:'

s 1 "SELECT sum(relpages)
FROM pg_class 
WHERE relname IN ('flights','boarding_passes','aircrafts','seats');"

c 'Это число может служить грубой оценкой сверху для запроса, которому требуются все строки: обработка существенно большего числа страниц может говорить о том, что данные перебираются по нескольку раз.'

c 'Видно, что в данном случае план близок к оптимальному. Его тоже можно улучшить, но уже не так радикально (очевидный момент — недостаток оперативной памяти для хеш-соединений).'

###############################################################################
stop_here
cleanup
demo_end
