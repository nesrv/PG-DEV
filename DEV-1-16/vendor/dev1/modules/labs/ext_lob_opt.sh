#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Подготовка'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Расширение для просмотра буферного кеша:'
s 1 'CREATE EXTENSION pg_buffercache;'

c 'Создадим таблицу со столбцом типа bytea:'
s 1 'CREATE TABLE demo_bytea (filename text, data bytea);'

export FNAME="novikov_dbtech.jpg"
export FILENAME="/home/$OSUSER/covers/novikov_dbtech.jpg"

c 'Загрузим файл с одной из обложек книг в таблицу:'
s 1 "INSERT INTO demo_bytea VALUES (
    '$FNAME',
    pg_read_binary_file('$FILENAME')
);"

c "Этот же файл загрузим как большой объект и запомним его oid:"

s 1 "SELECT lo_import('$FILENAME') AS \"oid\";"
export LOID=`sudo -i -u $OSUSER psql -A -t -X -d $TOPIC_DB -c "SELECT loid FROM pg_largeobject WHERE pageno = 0"`

c 'Для чистоты эксперимента очистим таблицы и сбросим все грязные буферы на диск:'
s 1 'VACUUM (analyze) demo_bytea, pg_largeobject;'
s 1 'CHECKPOINT;'

###############################################################################
h '2. Изменение bytea'

c 'Добавим к значению нулевой байт:'
s 1 "UPDATE demo_bytea SET data = data || '\x00'::bytea;"

c "Сколько всего страниц в основном слое TOAST-таблицы?"

s 1 "SELECT reltoastrelid::regclass AS toast_table 
FROM pg_class 
WHERE oid = 'demo_bytea'::regclass;"
export TOAST_TABLE=`sudo -i -u $OSUSER psql -A -t -X -d $TOPIC_DB -c "SELECT reltoastrelid::regclass::text FROM pg_class WHERE oid = 'demo_bytea'::regclass;"`

s 1 "SELECT pg_relation_size('$TOAST_TABLE', 'main') / 8192 buffers;"

c "А сколько грязных буферов хранит страницы основного слоя?"

s 1 "SELECT count(*)
FROM pg_buffercache b
WHERE b.relfilenode = pg_relation_filenode('$TOAST_TABLE')
AND b.relforknumber = 0 -- основной слой
AND b.isdirty;"

c 'То есть после изменения одного байта все страницы TOAST-таблицы стали грязными.'

###############################################################################
h '3. Изменение большого объекта'

c 'Добавим в конец объекта нулевой байт:'

s 1 "SELECT size FROM pg_stat_file('$FILENAME');"
export FILESIZE=`sudo -i -u $OSUSER psql -A -t -X -d $TOPIC_DB -c "SELECT size FROM pg_stat_file('$FILENAME');"`

s 1 "SELECT lo_put($LOID, $FILESIZE, '\x00'::bytea);"

c 'Посчитаем грязные буферы таблицы pg_largeobject:'
s 1 "SELECT count(*)
FROM pg_buffercache b
WHERE b.relfilenode = pg_relation_filenode('pg_largeobject')
AND b.relforknumber = 0 -- основной слой
AND b.isdirty;"

c 'Грязным стал всего один буфер.'

###############################################################################

stop_here
cleanup
