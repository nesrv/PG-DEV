#!/bin/bash

. ../lib

init

psql_open A 1

start_here

###############################################################################
h '1. Нежурналируемая таблица'

e "sudo -u postgres mkdir ${H}/ts_dir"
s 1 "CREATE TABLESPACE ts LOCATION '${H}/ts_dir';"
s 1 "CREATE DATABASE data_lowlevel;"
s 1 '\c data_lowlevel'

s 1 "CREATE UNLOGGED TABLE u(n integer) TABLESPACE ts;"
s 1 "INSERT INTO u(n) SELECT n FROM generate_series(1,1000) n;"

s 1 "SELECT pg_relation_filepath('u');"
u_PATH=`s_bare 1 "SELECT pg_relation_filepath('u');"`

c 'Посмотрим на файлы таблицы.'
c 'Обратите внимание, что следующая команда ls выполняется от имени пользователя postgres. Чтобы повторить такую команду, удобно сначала открыть еще одно окно терминала и переключиться в нем на другого пользователя командой:'

e_fake "sudo -i -u postgres"

c 'И затем в этом же окне выполнить:'

eu postgres "ls -l $PGDATA_A/$u_PATH*"

c 'Удалим созданное табличное пространство:'

s 1 "DROP TABLE u;"
s 1 "DROP TABLESPACE ts;"
e "sudo -u postgres rm -rf ${H}/ts_dir"

###############################################################################
h '2. Таблица с текстовым столбцом'

s 1 "CREATE TABLE t(s text);"

s 1 '\d+ t'

c 'По умолчанию для типа text используется стратегия extended.'

c 'Изменим стратегию на external:'

s 1 "ALTER TABLE t ALTER COLUMN s SET STORAGE external;"
s 1 "INSERT INTO t(s) VALUES ('Короткая строка.');"
s 1 "INSERT INTO t(s) VALUES (repeat('A',3456));"

c 'Проверим toast-таблицу:'

s 1 "SELECT relname FROM pg_class WHERE oid = (
  SELECT reltoastrelid FROM pg_class WHERE relname='t'
);"

v_RELNAME=`s_bare 1 "SELECT relname FROM pg_class WHERE oid = (SELECT reltoastrelid FROM pg_class WHERE relname='t');"`

c 'Toast-таблица «спрятана», так как находится в схеме, которой нет в пути поиска. И это правильно, поскольку TOAST работает прозрачно для пользователя. Но заглянуть в таблицу все-таки можно:'

s 1 "SELECT chunk_id, chunk_seq, length(chunk_data)
FROM pg_toast.$v_RELNAME
ORDER BY chunk_id, chunk_seq;"

c 'Видно, что в TOAST-таблицу попала только длинная строка (два фрагмента, общий размер совпадает с длиной строки). Короткая строка не вынесена в TOAST просто потому, что в этом нет необходимости — версия строки и без этого помещается в страницу.'

###############################################################################
stop_here
cleanup
demo_end
