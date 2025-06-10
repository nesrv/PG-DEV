#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. База данных и таблица'

s 1 'CREATE DATABASE backup_overview;'
s 1 '\c backup_overview'
s 1 'CREATE TABLE t(n integer);'
s 1 'INSERT INTO t VALUES (1), (2), (3);'

###############################################################################
h '2. Логическая резервная копия'

c 'Создаем резервную копию:'
dump_file=~/tmp/backup_overview.dump  # очистка каталога - в init
e "pg_dump -f $dump_file -d backup_overview --create"

c 'Удаляем базу данных и восстанавливаем ее из копии:'

s 1 '\c postgres'
s 1 'DROP DATABASE backup_overview;'

e "psql -f $dump_file"

s 1 '\c backup_overview'
s 1 'SELECT * FROM t;'

###############################################################################
h '3. Физическая автономная резервная копия'

c 'Создаем резервную копию, выполняя «быструю» контрольную точку:'

backup_dir=~/tmp/backup  # очистка каталога - в init
e "rm -rf $backup_dir"
e "pg_basebackup --pgdata=$backup_dir --checkpoint=fast"

c "Убеждаемся, что второй сервер остановлен, и выкладываем резервную копию:"
pgctl_status R
e "sudo rm -rf $PGDATA_R"
e "sudo mv $backup_dir $PGDATA_R"
e "sudo chown -R postgres:postgres $PGDATA_R"

c 'Изменяем таблицу:'

s 1 'DELETE FROM t;'

c 'Запускаем сервер из резервной копии:'

pgctl_start R
psql_open R 2 -d backup_overview

s 2 'SELECT * FROM t;'

###############################################################################
stop_here
cleanup
demo_end
