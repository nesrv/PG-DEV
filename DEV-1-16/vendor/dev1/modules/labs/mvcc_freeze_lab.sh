#!/bin/bash

. ../lib

init

psql_open A 2

start_here

###############################################################################
h '1. Заморозка при COPY WITH FREEZE'

c 'Создаем таблицу и загружаем несколько строк в одной и той же транзакции:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "BEGIN;"
s 1 "CREATE TABLE t(n integer);"
ss 1 "COPY t FROM stdin WITH FREEZE;"
ss 1 "1"
ss 1 "2"
ss 1 "3"
s 1 '\.'
s 1 "COMMIT;"

c 'Проверяем версии строк:'

s 1 'CREATE EXTENSION pageinspect;'

s 1 "CREATE VIEW t_v AS
SELECT '(0,'||lp||')' as ctid,
       CASE lp_flags
         WHEN 0 THEN 'unused'
         WHEN 1 THEN 'normal'
         WHEN 2 THEN 'redirect to '||lp_off
         WHEN 3 THEN 'dead'
       END AS state,
       t_xmin AS xmin,
       age(t_xmin) AS xmin_age,
       CASE WHEN (t_infomask & 256) > 0 THEN 't' END AS xmin_c,
       CASE WHEN (t_infomask & 512) > 0 THEN 't' END AS xmin_a,
       t_xmax AS xmax,
       t_ctid
FROM heap_page_items(get_raw_page('t',0))
ORDER BY lp;"

s 1 "SELECT * FROM t_v;"

###############################################################################
h '2. COPY WITH FREEZE и изоляция'

c 'В другом сеансе начнем транзакцию с уровнем изоляции Repeatable Read.'

s 2 "\c $TOPIC_DB"
s 2 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
s 2 "SELECT pg_current_xact_id();"

c 'Обратите внимание, что эта транзакция не должна обращаться к таблице t.'

c 'Теперь опустошим таблицу и загрузим в нее новые строки в одной транзакции. Если бы параллельная транзакция прочитала содержимое t, команда TRUNCATE ожидала бы ее завершения.'

s 1 "BEGIN;"
s 1 "TRUNCATE t;"
ss 1 "COPY t FROM stdin WITH FREEZE;"
ss 1 "10"
ss 1 "20"
ss 1 "30"
s 1 '\.'
s 1 "COMMIT;"

c 'Теперь параллельная транзакция видит новые данные, хотя это и нарушает изоляцию:'

s 2 "SELECT * FROM t;"
s 2 "COMMIT;"
psql_close 2

###############################################################################
h '3. Аварийное срабатывание автоочистки'

c 'Предварительно заморозим все транзакции во всех базах. Для этого удобно воспользоваться командой vacuumdb:'

e 'vacuumdb --all --freeze'

c 'Максимальный возраст незамороженных транзакций по всем БД:'

s 1 "SELECT datname, datfrozenxid, age(datfrozenxid) FROM pg_database;"

c 'Отключаем автоочистку.'

s 1 "ALTER SYSTEM SET autovacuum = off;"

c 'Уменьшаем значения параметров:'

s 1 "ALTER SYSTEM SET vacuum_freeze_min_age = 1000;"
s 1 "ALTER SYSTEM SET vacuum_freeze_table_age = 10000;"
s 1 "ALTER SYSTEM SET autovacuum_freeze_max_age = 100000;"

c 'Требуется перезагрузка сервера.'

pgctl_restart A

psql_open A 1 $TOPIC_DB

c 'Получить большое количество транзакций можно разными способами; например, можно воспользоваться утилитой pgbench. Попросим ее инициализировать свои таблицы и выполнить 100000 транзакций.'

e "pgbench -i $TOPIC_DB"

c 'Ключ --protocol=prepared позволяет повторно использовать результат разбора запросов, с ним работа будет быстрее:'

e "pgbench -t 100000 -P 5 --protocol=prepared $TOPIC_DB"

c 'Видно, что возраст незамороженных транзакций превышает установленное пороговое значение (100000):'

s 1 "SELECT datname, datfrozenxid, age(datfrozenxid) FROM pg_database;"

c 'Теперь при выполнении команды VACUUM для любой таблицы будет запущен процесс автоочистки.'

s 1 "VACUUM t;"

c 'Среди процессов появился autovacuum worker:'

e "ps -o pid,command --ppid $(sudo head -n 1 $PGDATA_A/postmaster.pid)"

c 'И через некоторое время транзакции окажутся замороженными:'

wait_sql 1 "SELECT count(*) = 0 FROM pg_database WHERE age(datfrozenxid) > current_setting('vacuum_freeze_min_age')::int;"

s 1 "SELECT datname, datfrozenxid, age(datfrozenxid) FROM pg_database;"

###############################################################################

stop_here
cleanup
