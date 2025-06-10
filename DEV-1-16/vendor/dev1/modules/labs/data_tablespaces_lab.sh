#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Новое табличное пространство'

e "sudo -u postgres mkdir ${H}/ts_dir"
s 1 "CREATE TABLESPACE ts LOCATION '${H}/ts_dir';"

###############################################################################
h '2. Табличное пространство по умолчанию для template1'

s 1 "ALTER DATABASE template1 SET TABLESPACE ts;"

###############################################################################
h '3. Новая база данных и проверка'

s 1 "CREATE DATABASE db;"
s 1 "SELECT spcname
FROM pg_tablespace
WHERE oid = (SELECT dattablespace FROM pg_database WHERE datname = 'db');"

c 'Табличное пространство по умолчанию — ts.'
c 'Вывод: если нет явного указания, табличное пространство по умолчанию определяется шаблоном, из которого клонируется новая база данных.'

###############################################################################
h '4. Символическая ссылка'

s 1 "SELECT oid AS tsoid FROM pg_tablespace WHERE spcname = 'ts';"
export TSOID=`s_bare 1 "SELECT OID AS tsoid FROM pg_tablespace WHERE spcname = 'ts';"`

e "sudo -u postgres ls -l $PGDATA_A/pg_tblspc/$TSOID"

###############################################################################
h '5. Удаление табличного пространства'

s 1 'ALTER DATABASE template1 SET TABLESPACE pg_default;'
s 1 'DROP DATABASE db;'
s 1 'DROP TABLESPACE ts;'
e "sudo -u postgres rm -rf ${H}/ts_dir"

###############################################################################
stop_here
cleanup
demo_end
