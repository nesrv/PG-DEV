#!/bin/bash

. ../lib
init

pgctl_start B

start_here
###############################################################################
h '1. Базы данных и объекты'

s 1 'CREATE DATABASE db1;'
s 1 '\c db1'
s 1 'CREATE TABLE t1(n integer);'
s 1 'INSERT INTO t1 VALUES (1), (2), (3);'
s 1 'CREATE VIEW v1 AS SELECT * FROM t1;'

s 1 'CREATE DATABASE db2;'
s 1 '\c db2'
s 1 'CREATE TABLE t2(n integer);'
s 1 'INSERT INTO t2 VALUES (1), (2), (3);'
s 1 'CREATE VIEW v2 AS SELECT * FROM t2;'

###############################################################################
h '2. Копия глобальных объектов'
e "pg_dumpall --clean --globals-only -U postgres -f /home/student/tmp/alpha_globals.sql"

###############################################################################
h '3. Копии баз данных'

c 'Здесь мы ограничимся теми базами данных, которые создали сами.'
e "pg_dump --jobs=2 --format=directory -d db1 -f /home/student/tmp/db1.directory"
e "pg_dump --jobs=2 --format=directory -d db2 -f /home/student/tmp/db2.directory"

###############################################################################
h '4. Восстановление кластера'

c 'Сначала восстанавливаем глобальные объекты:'
e "psql -p 5433 -U postgres -f /home/student/tmp/alpha_globals.sql 2> /dev/null"

c 'Затем восстанавливаем базы данных:'
e "pg_restore -p 5433 -d postgres --create --jobs=2 /home/student/tmp/db1.directory"
e "pg_restore -p 5433 -d postgres --create --jobs=2 /home/student/tmp/db2.directory"

c 'Проверим:'
psql_open B 2 -p 5433
s 2 '\c db1'
s 2 '\d'
s 2 '\c db2'
s 2 '\d'

###############################################################################
h '5. Ломаем COPY'

c 'Например, можно установить отображение неопределенных значений, совпадающее с какими-либо данными:'
s 1 'CREATE TABLE anticopy(s text);'
s 1 "INSERT INTO anticopy(s) VALUES ('N'), (NULL);"
s 1 "COPY anticopy TO stdout WITH (NULL 'N');"

c 'Вывод двух разных значений теперь неотличим друг от друга.'
c 'Осторожнее с изменением формата по умолчанию!'

###############################################################################
stop_here
cleanup
demo_end
