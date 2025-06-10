#!/bin/bash

. ../lib
init

start_here 5

###############################################################################
h 'Сбор статистики по операторам и планам'

psql_open A 1

c 'Подключим разделяемую библиотеку pgpro_stats:'
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pgpro_stats';"
pgctl_restart A

c 'Создадим тестовую базу данных на основе demo:'
psql_open A 1
s 1 "CREATE DATABASE $TOPIC_DB TEMPLATE demo;"

c 'Для удобства настроим путь поиска:'
s 1 "ALTER DATABASE $TOPIC_DB SET search_path TO bookings, public;"

c 'В схеме bookings копия стандартной демобазы минимального размера.'
s 1 "\c $TOPIC_DB"
s 1 '\dt'

c 'Подключим расширение:'
s 1 'CREATE EXTENSION pgpro_stats;'

c 'Выполним несколько запросов к таблице билетов tickets, предварительно добавив индекс по фамилиям пассажиров.'
s 1 'CREATE INDEX ticket_pname ON tickets(passenger_name);'

c 'Пара запросов с параллельным последовательным сканированием таблицы.'
s 1 "SELECT count(book_ref) FROM tickets WHERE passenger_name < 'Z';"
s 1 "SELECT count(book_ref) FROM tickets WHERE passenger_name < 'Y';"

c 'Посмотрим, что накопилось в статистике операторов.'

s 1 "SELECT query, plan, calls
FROM pgpro_stats_statements 
WHERE query LIKE 'SELECT count(book_ref) FROM tickets WHERE passenger_name%' \gx"

c 'Поле calls содержит информацию о количестве выполнений оператора.'
c 'Операторы DML объединяются в одну запись, если они имеют одинаковую структуру.'

c 'В следующих запросах используется индексный доступ:'
s 1 "SELECT count(book_ref) FROM tickets WHERE passenger_name > 'Z';"
s 1 "SELECT count(book_ref) FROM tickets WHERE passenger_name > 'Y';"

c 'Теперь у нас два разных плана.'
s 1 "SELECT query, plan, calls
FROM pgpro_stats_statements 
WHERE query LIKE 'SELECT count(book_ref) FROM tickets WHERE passenger_name%' \gx"

p

c 'Для пользователя student получим агрегированную статистику по использованию некоторых системных ресурсов, а также по количеству выполненных запросов и событий ожидания.'
s 1 "SELECT object_type, object_name, queries_executed, total_exec_time, 
  (total_exec_rusage).reads, (total_exec_rusage).writes, 
  (total_exec_rusage).user_time, (total_exec_rusage).system_time,
  jsonb_pretty(wait_stats) AS wait_stats
FROM pgpro_stats_totals
WHERE object_type = 'user'
  AND object_id = 'student'::regrole \gx"

c 'В выводе этого запроса получены количество выполненных запросов, общее время выполнения запросов, а также несколько полей записи в столбце total_exec_rusage:'
ul 'reads — количество байтов, прочитанное из файловой системы;'
ul 'writes — количество байтов, записанное в файловую систему;'
ul 'user_time — время, потраченное на работу запроса в непривилегированном режиме (user space);'
ul 'system_time — время, потраченное на работу запроса на стороне ядра ОС (kernel space).'

c 'Столбец total_exec_rusage составного типа pgpro_stats_rusage содержит статистику использования ресурсов на этапах планирования и выполнения запросов.'

p

c 'Собранная статистика сбрасывается функцией pgpro_stats_statements_reset для заданного пользователя (userid), базы данных (dbid), запроса (queryid) или плана (planid). Если не указать ни один аргумент, будет очищена вся статистика:'
s 1 "SELECT pgpro_stats_statements_reset();"

c 'Статистика по запросам удалена:'
s 1 "SELECT query, plan, calls
FROM pgpro_stats_statements 
WHERE query LIKE 'SELECT count(*) FROM tickets WHERE passenger_name%' \gx"

c 'Агрегированная статистика для заданного типа и идентификатора объекта очищается функцией pgpro_stats_totals_reset.'
c 'Например, сбросим агрегатную статистику по роли student:'
s 1 "SELECT pgpro_stats_totals_reset('user', 'student'::regrole::bigint);"

s 1 "SELECT object_type, object_name, queries_executed, total_exec_time, 
  (total_exec_rusage).reads, (total_exec_rusage).writes, 
  (total_exec_rusage).user_time, (total_exec_rusage).system_time,
  jsonb_pretty(wait_stats) AS wait_stats
FROM pgpro_stats_totals
WHERE object_type = 'user'
  AND object_id = 'student'::regrole \gx"
c 'После сброса статистики был только что выполнен единственный запрос. Поэтому queries_executed равно единице.'

c 'Статистика по базе данных сохранилась, так как она не была стерта:'
s 1 "SELECT object_type, object_name, queries_executed, total_exec_time, 
  (total_exec_rusage).reads, (total_exec_rusage).writes, 
  (total_exec_rusage).user_time, (total_exec_rusage).system_time,
  jsonb_pretty(wait_stats) AS wait_stats
FROM pgpro_stats_totals
WHERE object_type = 'database' 
  AND object_id = (SELECT oid FROM pg_database WHERE datname = '$TOPIC_DB') \gx"

P 7
###############################################################################

h 'Сбор дополнительных метрик'

c 'Предположим, что требуется раз в 30 секунд собирать количество выполнений контрольной точки по требованию.'
c 'Запишем параметры в файл conf.d/metrics.conf в каталоге данных кластера и перезапустим СУБД.'

fu postgres $PGDATA_A/conf.d/metrics.conf conf << EOF
pgpro_stats.metric_1_name = 'bgwriter'
pgpro_stats.metric_1_query = 'SELECT * FROM pg_stat_bgwriter'
pgpro_stats.metric_1_db = '$TOPIC_DB'
pgpro_stats.metric_1_user = 'student'
pgpro_stats.metric_1_period = '30s'
EOF

c 'Добавленная метрика — первая, поэтому N=1.'

pgctl_restart A

psql_open A 1 -p 5432 -d $TOPIC_DB

c 'Заглянем в представление для дополнительных метрик:'
s 1 "SELECT metric_number, db_name, ts, value #> '{0,checkpoints_req}' AS checkpoints_req
FROM pgpro_stats_metrics;"

c 'Столбец value содержит результат запроса, вычисляющего метрику, в виде массива объектов jsonb. Здесь извлечен первый по порядку (нулевой) элемент, в котором по ключу checkpoints_req получено искомое значение.'

c 'Во всех купленных авиабилетах изменим фамилии пассажиров так, чтобы первая буква была заглавной, а остальные — строчными:'
s 1 "UPDATE tickets SET passenger_name = initcap(passenger_name);"

max_qty=`s_bare 1 "SELECT max((value #> '{0,checkpoints_req}')::bigint) FROM pgpro_stats_metrics;"`

c 'Выполним контрольную точку и немного подождем.'
s 1 "CHECKPOINT;"

wait_sql 1 "SELECT count(*) > 0 FROM pgpro_stats_metrics WHERE (value #> '{0,checkpoints_req}')::bigint > $max_qty;" 80

c 'В представлении pgpro_stats_metrics появится одна или несколько записей. Обратите внимание на значение checkpoints_req:'
s 1 "SELECT metric_number, db_name, ts, value #> '{0,checkpoints_req}' AS checkpoints_req
FROM pgpro_stats_metrics;"

c 'Удалим настройки дополнительных метрик:'
eu postgres "rm $PGDATA_A/conf.d/metrics.conf"

c 'Снова перезагрузим сервер.'
pgctl_restart A

P 9
###############################################################################
h 'Статистика очистки'

psql_open A 1 -p 5432 -d $TOPIC_DB

c 'Выключим автоочистку для таблицы tickets:'
s 1 "ALTER TABLE tickets SET (autovacuum_enabled = off);"

c 'Поскольку статистика по очистке собирается ядром СУБД, для ее сброса используется стандартная функция:'
s 1 "SELECT pg_stat_reset();"

c 'Статистика очистки для таблицы tickets отсутствует:'
s 1 "SELECT * FROM pgpro_stats_vacuum_tables(
  (SELECT oid FROM pg_database WHERE datname = '$TOPIC_DB'),
  'tickets'::regclass
) \gx"

c 'Вернем фамилии к написанию в верхнем регистре и выполним очистку.'
s 1 "UPDATE tickets SET passenger_name = upper(passenger_name);"
s 1 "VACUUM tickets;"

c 'Немного ожидания...'
wait_sql 1 "SELECT count(*) > 0
FROM pgpro_stats_vacuum_tables(
	(SELECT oid FROM pg_database WHERE datname = current_database()),
	'tickets'::regclass
);"

c 'Снова проверим статистику очистки для таблицы tickets. Теперь статистика очистки собрана:'
s 1 "SELECT * FROM pgpro_stats_vacuum_tables(
  (SELECT oid FROM pg_database WHERE datname = '$TOPIC_DB'),
  'tickets'::regclass
) \gx"

c 'Вернем автоочистку для таблицы tickets:'
s 1 "ALTER TABLE tickets SET (autovacuum_enabled = on);"

# Закрываю сессию для следующей демонстрации по аннулированию кэша.
psql_close 1

P 11
###############################################################################
h 'Аннулирование кешей'

c 'Откроем новый сеанс и получим PID обслуживающего процесса:'
psql_open A 1 -d $TOPIC_DB
s 1 "SELECT pg_backend_pid();"

c 'Пока ни одного сообщения об аннулировании кеша нет:'
s 1 "SELECT object_type, (inval_msgs).total
FROM pgpro_stats_totals
WHERE object_type = 'backend'
  AND object_id = $PID1;"

c 'Изменим, например, параметр хранения таблицы.'
s 1 "ALTER TABLE seats SET (autovacuum_enabled = on);"

c 'Сообщения об аннулировании кеша, сгенерированные текущим обслуживающим процессом:'
s 1 "SELECT object_type,
  (inval_msgs).total,
  (inval_msgs).catcache,
  (inval_msgs).relcache
FROM pgpro_stats_totals
    WHERE object_type = 'backend'
      AND object_id = $PID1;"
c 'Здесь:'
ul 'total — общее число сообщений аннулирования;'
ul 'catcache — число сообщений избирательного аннулирования кеша каталога;'
ul 'relcache — число сообщений избирательного аннулирования кеша отношений.'

psql_close 1

P 13
###############################################################################
h 'Трассировка сеансов'

psql_open A 1 -d $TOPIC_DB
c 'Откроем второй сеанс и получим PID обслуживающего процесса.'
psql_open A 2 -d $TOPIC_DB
s 2 "SELECT pg_backend_pid();"

c 'Добавим фильтр pa1, который будет записывать в файл трассировки pa1.trace вывод EXPLAIN ANALYZE для каждой команды, выполняющейся во втором сеансе:'
s 1 "SELECT pgpro_stats_trace_insert(
  'alias', 'pa1', 
  'database_name', current_database(),
  'pid', $PID2,
  'explain_analyze', true,
  'tracefile', 'pa1'
);"

c 'Проверим получившийся фильтр трассировки:'
s 1 "SELECT * from pgpro_stats_trace_show() \gx"

c 'Во втором сеансе выполним запрос.'
s 2 "SELECT count(*) FROM tickets WHERE passenger_name > 'Z';"

c 'Закроем второй сеанс и проверим файл трассировки.'
psql_close 2
eu postgres "cat $PGDATA_A/pg_stat/pa1.trace"

c 'Удалим фильтр трассировки.'
s 1 "SELECT pgpro_stats_trace_delete(1);"

###############################################################################

stop_here
cleanup
demo_end
