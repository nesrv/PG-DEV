#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Табличные пространства и таблица'

c 'Создаем базу данных:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Табличное пространство:'

e "sudo mkdir $H/ts_dir"
e "sudo chown postgres $H/ts_dir"
s 1 "CREATE TABLESPACE ts LOCATION '$H/ts_dir';"

c 'Создаем таблицу:'

s 1 'CREATE TABLE t(n integer) TABLESPACE ts;'
s 1 "INSERT INTO t SELECT 1 FROM generate_series(1,1000);"

###############################################################################
h '2. Размер данных'

c 'Объем базы данных:'

s 1 "SELECT pg_size_pretty(pg_database_size('$TOPIC_DB')) AS db_size;"

c 'Размер таблицы:'

s 1 "SELECT pg_size_pretty(pg_total_relation_size('t')) AS t_size;"

c 'Объем табличных пространств:'

s 1 "SELECT
    pg_size_pretty(pg_tablespace_size('pg_default')) AS pg_default_size,
    pg_size_pretty(pg_tablespace_size('ts')) AS ts_size;"

c 'Размер табличного пространства больше размера таблицы на 4kB из-за особенностей вычисления размера содержимого каталога в Linux.'

###############################################################################
h '3. Перенос таблицы'

c 'Перенесем таблицу:'

s 1 'ALTER TABLE t SET TABLESPACE pg_default;'

c 'Новый объем табличных пространств:'

s 1 "SELECT
    pg_size_pretty(pg_tablespace_size('pg_default')) AS pg_default_size,
    pg_size_pretty(pg_tablespace_size('ts')) AS ts_size;"

###############################################################################
h '4. Удаление табличного пространства'

c 'Удаляем табличное пространство...'

s 1 'DROP TABLESPACE ts;'

c '...и каталог, где были размещены его данные:'

e "sudo rm -rf $H/ts_dir"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
