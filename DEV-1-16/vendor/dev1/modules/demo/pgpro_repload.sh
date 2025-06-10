#!/bin/bash


. ../lib
init

start_here 8
###############################################################################

h 'Сбор статистики по операторам и планам с помощью pgpro_stats.'

c 'Подключим разделяемую библиотеку pgpro_stats.'
psql_open A 1
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pgpro_stats';"
psql_close 1
pgctl_restart A

c 'Создадим тестовую базу данных на основе demo.'
psql_open A 1
s 1 "CREATE DATABASE demotest TEMPLATE demo;"

c 'Для удобства настроим search_path.'
s 1 "ALTER DATABASE demotest SET search_path TO bookings, public;"

c 'В схеме bookings копия стандартной демо-базы минимального размера.'
s 1 '\c demotest'
s 1 '\dt'

c 'Подключим расширение.'
s 1 'CREATE EXTENSION pgpro_stats;'

c 'Выполним несколько запросов к таблице купленных билетов bookings.tickets, предварительно добавив индекс по фамилиям пассажиров.'
s 1 'CREATE INDEX ticket_pname ON tickets(passenger_name);'
s 1 'ANALYZE tickets;'

c 'Пара запросов с распараллеленным последовательным сканированием таблицы.'
s 1 "SELECT count(*) FROM tickets WHERE passenger_name < 'Z';"
s 1 "SELECT count(*) FROM tickets WHERE passenger_name < 'Y';"

c 'Посмотрим, что накопилось в статистике операторов.'
s 1 "SELECT query, plan, calls FROM pgpro_stats_statements 
WHERE query LIKE 'SELECT count(*) FROM tickets WHERE passenger_name%' \gx"
c 'Поле count содержит информацию о количестве выполнений оператора.'
c 'Операторы DML объединяются в одну запись если они имеют одинаковую структуру запросов.'

c 'Теперь должен использоваться индекс.'
s 1 "SELECT count(*) FROM tickets WHERE passenger_name > 'Z';"
s 1 "SELECT count(*) FROM tickets WHERE passenger_name > 'Y';"

c 'Теперь должно быть видно два разных плана.'
s 1 "SELECT query, plan, calls FROM pgpro_stats_statements 
WHERE query LIKE 'SELECT count(*) FROM tickets WHERE passenger_name%' \gx"

c 'Получим агрегированную статистику по роли student.'
s 1  "SELECT object_type, object_id, object_name, queries_planned, total_plan_time,
 total_plan_rusage, queries_executed, total_exec_time, total_exec_rusage, rows, shared_blks_hit,
 shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied,
 local_blks_written, temp_blks_read, temp_blks_written, blk_read_time, blk_write_time,
 jsonb_pretty(wait_stats) as wait_stats, inval_msgs, cache_resets
 FROM pgpro_stats_totals WHERE object_type = 'user' AND object_id = 'student'::regrole \gx"

c 'А теперь - по всей базе данных. REG преобразования для получения oid базы данных не существует.'
s 1  "SELECT object_type, object_id, object_name, queries_planned, total_plan_time,
 total_plan_rusage, queries_executed, total_exec_time, total_exec_rusage, rows, shared_blks_hit,
 shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied,
 local_blks_written, temp_blks_read, temp_blks_written, blk_read_time, blk_write_time,
 jsonb_pretty(wait_stats) as wait_stats, inval_msgs, cache_resets
FROM pgpro_stats_totals WHERE object_type = 'database' 
AND object_id = (SELECT oid FROM pg_database WHERE datname = 'demotest') \gx"

psql_close 1

P 10
###############################################################################

h 'Сбор дополнительных метрик.'

c 'Предположим, что требуется с периодичностью раз в 30с собирать статистику по процессам фоновой записи и контрольной точки, ввиду ее важности для мониторинга экземпляра.'
c 'Добавим в postgresql.auto.conf необходимые параметры и перезапустим СУБД.'
e "cat << EOF | sudo -u postgres tee -a $PGDATA_A/postgresql.auto.conf
pgpro_stats.metric_1_name = 'bgwriter_metr'
pgpro_stats.metric_1_query = 'SELECT * FROM pg_stat_bgwriter'
pgpro_stats.metric_1_db = 'demotest'
pgpro_stats.metric_1_user = student
pgpro_stats.metric_1_period = '30s'
EOF"
c 'Добавленная метрика - первая, поэтому N=1.'

pgctl_restart A

psql_open A 1 -p 5432 -d demotest

c 'Заглянем в представление для дополнительных метрик.'
s 1 "SELECT metric_number, metric_number, db_name, ts, jsonb_pretty(value) as value 
FROM pgpro_stats_metrics \gx"

c 'Во всех купленных авиабилетах изменим фамилии пассажиров так, чтобы первая буква была заглавной, а остальные - прописными.'
s 1 "UPDATE tickets SET passenger_name =  initcap(passenger_name);"

c 'Выполним контрольную точку и подождем 30 секунд.'
s 1 "CHECKPOINT;"
#e 'sleep 30'

c 'В представлении pgpro_stats_metrics должны быть видна соответствующая запись.'
c 'Обратите внимание на значение checkpoints_req.'
s 1 "SELECT metric_number, metric_number, db_name, ts, jsonb_pretty(value) as value 
FROM pgpro_stats_metrics \gx"

psql_close 1

# Для дальнейшего продолжения демонстрации.
c 'Вернем содержимое postgresql.auto.conf к его исходному состоянию.'
eu postgres "sed -i '/^pgpro_stats/d' $PGDATA_A/postgresql.auto.conf"

c 'Снова перезагрузим сервер.'
pgctl_restart A

P 13
###############################################################################

h 'Статистика очистки и сброс статистик.'

psql_open A 1 -p 5432 -d demotest

c 'Проверим, сохранилась ли статистика по выполненным запросам.'
s 1 "SELECT query, plan, calls FROM pgpro_stats_statements 
WHERE query LIKE 'SELECT count(*) FROM tickets WHERE passenger_name%' \gx"

c 'Получим агрегированную статистику по роли student.'
s 1  "SELECT object_type, object_id, object_name, queries_planned, total_plan_time,
 total_plan_rusage, queries_executed, total_exec_time, total_exec_rusage, rows, shared_blks_hit,
 shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied,
 local_blks_written, temp_blks_read, temp_blks_written, blk_read_time, blk_write_time,
 inval_msgs, cache_resets
 FROM pgpro_stats_totals WHERE object_type = 'user' AND object_id = 'student'::regrole \gx"

c 'Сбросим агрегатную статистику по пользователю student.'
s 1 "select pgpro_stats_totals_reset('user', 'student'::regrole::bigint);"

c 'Снова проверим агрегированную статистику по роли student.'
s 1  "SELECT object_type, object_id, object_name, queries_planned, total_plan_time,
 total_plan_rusage, queries_executed, total_exec_time, total_exec_rusage, rows, shared_blks_hit,
 shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied,
 local_blks_written, temp_blks_read, temp_blks_written, blk_read_time, blk_write_time,
 inval_msgs, cache_resets
 FROM pgpro_stats_totals WHERE object_type = 'user' AND object_id = 'student'::regrole \gx"

c 'Сбросим агрегатную статистику по пользователю student.'
s 1 "select pgpro_stats_totals_reset('user', 'student'::regrole::bigint);"

c 'А по всей базе данных статистика должна остаться.'
s 1  "SELECT object_type, object_id, object_name, queries_planned, total_plan_time,
 total_plan_rusage, queries_executed, total_exec_time, total_exec_rusage, rows, shared_blks_hit,
 shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied,
 local_blks_written, temp_blks_read, temp_blks_written, blk_read_time, blk_write_time,
 inval_msgs, cache_resets
FROM pgpro_stats_totals WHERE object_type = 'database' 
AND object_id = (SELECT oid FROM pg_database WHERE datname = 'demotest') \gx"

c 'Сбросим всю агрегатную статистику.'
s 1 "select pgpro_stats_totals_reset();"

c 'Теперь агрегатной статистики нет.'
s 1  "SELECT object_type, object_id, object_name, queries_planned, total_plan_time,
 total_plan_rusage, queries_executed, total_exec_time, total_exec_rusage, rows, shared_blks_hit,
 shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied,
 local_blks_written, temp_blks_read, temp_blks_written, blk_read_time, blk_write_time,
 inval_msgs, cache_resets
FROM pgpro_stats_totals WHERE object_type = 'database' 
AND object_id = (SELECT oid FROM pg_database WHERE datname = 'demotest') \gx"

c 'А статистика по выполненным запросам? Она на месте.'
s 1 "SELECT query, plan, calls FROM pgpro_stats_statements 
WHERE query LIKE 'SELECT count(*) FROM tickets WHERE passenger_name%' \gx"

c 'Сбросим всю собранную статистику по выполненным запросам.'
s 1 "SELECT pgpro_stats_statements_reset();"

c 'Проверим статистику по запросам теперь.'
s 1 "SELECT query, plan, calls FROM pgpro_stats_statements 
WHERE query LIKE 'SELECT count(*) FROM tickets WHERE passenger_name%' \gx"

# Статистика по вакууму.
c 'По операциям очистки источник статистики - ядро СУБД.'
c 'Выключим автовакуум для таблицы tickets.'
s 1 "ALTER TABLE tickets SET (autovacuum_enabled = off);"

c 'Сбросим системную статистику, собранную ядром СУБД.'
s 1 "select pg_stat_reset();"

c 'Проверим статистику очистки для таблицы tickets. Она должна отсутствовать.'
s 1 "SELECT pgpro_stats_vacuum_tables(
(SELECT oid FROM pg_database WHERE datname = 'demotest'), 'tickets'::regclass);"

c 'Вернем фамилии к написанию в верхнем регистре.'
s 1 "UPDATE tickets SET passenger_name =  upper(passenger_name);"

c 'Выполним очистку.'
s 1 "VACUUM tickets;"

c 'Снова проверим статистику очистки для таблицы tickets. Теперь статистика очистки собрана.'
s 1 "SELECT * FROM pgpro_stats_vacuum_tables(
(SELECT oid FROM pg_database WHERE datname = 'demotest'), 'tickets'::regclass) \gx"

c 'Вернем автовакуум для таблицы tickets.'
s 1 "ALTER TABLE tickets SET (autovacuum_enabled = on);"

psql_close 1

P 18
###############################################################################

h 'Установка расширения pgpro_pwr.'

c 'ПО расширения pgpro_pwr уже установлено в виртуальной машине.'

psql_open A 1

c 'Сбросим все изменения в postgresql.auto.conf и добавим необходимые для pgpro_pwr.'
s 1 "ALTER SYSTEM RESET ALL;"
s 1 "ALTER SYSTEM SET shared_preload_libraries = pg_wait_sampling, pgpro_stats;"
s 1 "ALTER SYSTEM SET track_io_timing = 'on';"
s 1 "ALTER SYSTEM SET track_functions = 'all';"

c 'Перезагрузим сервер.'
psql_close 1
pgctl_restart A

psql_open A 1 -p 5432 -d demotest

c 'Создадим схему для хранения объектов расширения и установим расширение.'
s 1 "CREATE SCHEMA profile;"
s 1 "CREATE EXTENSION pgpro_pwr SCHEMA profile CASCADE;"
s 1 "CREATE EXTENSION pg_wait_sampling;"
s 1 "\dx"

psql_close 1

P 26
###############################################################################

h 'Получение выборки, выборочной линии и отчетов.'

c 'Откроем два сеанса.'
psql_open A 1 -p 5432 -d demotest
psql_open A 2 -p 5432 -d demotest

c 'Получим первую выборку. Предыдущая статистика сбрасывается.'
s 1 "SELECT profile.take_sample();"

c 'Во втором сеансе выполним запрос.'
s 2 "SELECT count(*) FROM tickets WHERE passenger_name < 'Y';"

c 'Теперь получим вторую выборку - в нее попадут данные о нагрузке после первой выборки.'
s 1 "SELECT profile.take_sample();"

c 'Во втором сеансе выполним другой запрос.'
s 2 "SELECT count(*) FROM tickets WHERE passenger_name > 'Y';"

c 'А сейчас получим третью выборку - в нее попадут данные о нагрузке после второй выборки.'
s 1 "SELECT profile.take_sample();"

c 'Получим список выборок.'
s 1 "SELECT * FROM profile.show_samples();"

c 'Сформируем из имеющихся выборок две выборочные линии.'
s 1 "SELECT profile.create_baseline(baseline=>'BaseLine1', start_id=>1, end_id=>2);"
s 1 "SELECT profile.create_baseline(baseline=>'BaseLine2', start_id=>2, end_id=>3);"

c 'Получим список выборочных линий.'
s 1 "SELECT * FROM profile.show_baselines();"

c 'Получим отчет. Для построения обычного отчета достаточно указать две выборки или одну выборочную линию.'
e "psql -d demotest -Aqtc 'SELECT profile.get_report(1,2)' -o /tmp/report_1_2.html"
ei "firefox /tmp/report_1_2.html >& /dev/null"

c 'Получим разностный отчет. Используем две выборочные линии.'
#e 'psql -d demotest -Aqtc "SELECT profile.get_diffreport(\'BaseLine1\',\'BaseLine2\')" -o /tmp/report_diff.html'
[ -e /tmp/report_diff.html ] && sudo rm /tmp/report_diff.html
s 1 "COPY (SELECT profile.get_diffreport('BaseLine1','BaseLine2')) TO '/tmp/report_diff.html';"
ei "firefox /tmp/report_diff.html >& /dev/null"

psql_close 2
psql_close 1

###############################################################################
stop_here

cleanup
demo_end
