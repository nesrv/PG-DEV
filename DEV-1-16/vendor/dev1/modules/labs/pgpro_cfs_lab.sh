#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Сжатое табличное пространство'

e "sudo mkdir $H/ts_dir"
e "sudo chown postgres: $H/ts_dir"

s 1 "CREATE TABLESPACE cts LOCATION '$H/ts_dir' WITH (compression=zstd);"
s 1 "ALTER SYSTEM SET cfs_level=14;"
s 1 "SELECT pg_reload_conf();"
s 1 "\db+ cts"

########################################################################
h '2. База данных'

s 1 "CREATE DATABASE $TOPIC_DB TEMPLATE template0 TABLESPACE cts;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE SCHEMA bookings;"

c "Загружаем определение таблицы и ее строки в новую базу:"

e "${BINPATH_A}pg_dump -d demo --table=tickets --section=pre-data --section=data | psql -d $TOPIC_DB" sh

c 'Размер таблицы и степень сжатия:'

s 1 "ANALYZE bookings.tickets;"

s 1 "SELECT relname, relpages,
  pg_size_pretty(relpages*8192::numeric) original,
  pg_size_pretty(pg_table_size(oid)) compressed,
  cfs_compression_ratio(oid) ratio
FROM pg_class
WHERE relname = 'tickets'
;"

p

########################################################################
h 'Удаление табличного пространства'

s 1 "\c student"
s 1 "DROP DATABASE $TOPIC_DB;"
s 1 "DROP TABLESPACE cts;"
e "sudo rm -rf $H/ts_dir"

########################################################################

stop_here
cleanup
