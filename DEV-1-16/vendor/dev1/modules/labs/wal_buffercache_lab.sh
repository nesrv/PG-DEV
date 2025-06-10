#!/bin/bash

. ../lib

init

s 1 "CHECKPOINT;" # чтобы случайно не влез посреди выполнения

start_here

###############################################################################
h '1. Таблица в кеше'

c 'Создадим таблицу:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE TABLE t(n integer);"
s 1 "INSERT INTO t SELECT 1 FROM generate_series(1,10000);"

c 'Выполним VACUUM — это обеспечит нам наличие всех слоев:'

s 1 'VACUUM t;'

c 'Сколько страниц на диске занимает таблица?'

s 1 "SELECT setting FROM pg_settings WHERE name = 'block_size';"
export BLKSIZE=$(s_bare 1 "SELECT setting FROM pg_settings WHERE name = 'block_size';")

s 1 "SELECT pg_table_size('t') / $BLKSIZE;"

c 'Из них основной слой:'

s 1 "SELECT pg_relation_size('t','main') / $BLKSIZE;"

c 'Карта свободного пространства:'

s 1 "SELECT pg_relation_size('t','fsm') / $BLKSIZE;"

c 'И карта видимости:'

s 1 "SELECT pg_relation_size('t','vm') / $BLKSIZE;"

c 'Сколько буферов в кеше занимает таблица?'

s 1 'CREATE EXTENSION pg_buffercache;'
s 1 "SELECT CASE relforknumber
         WHEN 0 THEN 'main'
         WHEN 1 THEN 'fsm'
         WHEN 2 THEN 'vm'
       END relfork,
       count(*)
FROM   pg_buffercache b,
       pg_class c
WHERE  b.reldatabase = (
         SELECT oid FROM pg_database WHERE datname = current_database()
       )
AND    c.oid = 't'::regclass
AND    b.relfilenode = c.relfilenode
GROUP BY 1;"

###############################################################################
h '2. Грязные буферы в кеше'

s 1 "SELECT buffers_dirty FROM pg_buffercache_summary();"

c 'Выполним контрольную точку:'

s 1 'CHECKPOINT;'
s 1 "SELECT buffers_dirty FROM pg_buffercache_summary();"

c 'Грязных буферов не осталось. Подробнее о контрольной точке рассказывается в отдельной теме.'

###############################################################################
h '3. Автоматический прогрев кеша'

c 'Подключим библиотеку pg_prewarm и перезапустим сервер.'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_prewarm';"

pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'Теперь отдельный фоновый процесс будет сбрасывать на диск список страниц, находящихся в буферном кеше, раз в pg_prewarm.autoprewarm_interval единиц времени.'

e 'ps -o pid,command --ppid $(sudo head -n 1 '$PGDATA_A'/postmaster.pid) | grep prewarm'

c 'Прочитаем таблицу t в буферный кеш:'

s 1 "CREATE EXTENSION pg_prewarm;"
s 1 "SELECT pg_prewarm('t');"
s 1 "SELECT count(*)
FROM pg_buffercache
WHERE relfilenode = pg_relation_filenode('t'::regclass);"

c 'Можно либо подождать, либо сбросить список страниц вручную:'

s 1 "SELECT autoprewarm_dump_now();"

c 'В файл записываются идентификаторы базы данных, табличного пространства и файла, номер слоя и номер блока:'

e "sudo head -n 10 $PGDATA_A/autoprewarm.blocks"

c 'Снова перезапустим сервер.'

pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'После запуска фоновый процесс прочитает в буферный кеш все страницы, указанные в файле.'

s 1 "SELECT count(*)
FROM pg_buffercache
WHERE relfilenode = pg_relation_filenode('t'::regclass);"

###############################################################################

stop_here
cleanup
