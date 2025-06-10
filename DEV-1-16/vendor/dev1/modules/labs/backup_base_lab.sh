#!/bin/bash

. ../lib
init

start_here
###############################################################################
h '1. Табличное пространство и база данных'

eu student "sudo -u postgres mkdir $H/ts_dir"

c 'Табличные пространства может создавать только суперпользователь:'
eu student "psql -U postgres -c \"CREATE TABLESPACE ts LOCATION '$H/ts_dir'\""
eu student "psql -U postgres -c \"ALTER TABLESPACE ts OWNER TO student\""

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE TABLE t(s text) TABLESPACE ts;"
s 1 "INSERT INTO t VALUES ('Привет, мир!');"

export TSOID=`psql -A -t -X -c "SELECT OID FROM pg_tablespace WHERE spcname = 'ts';"`

###############################################################################
h '2. Базовая резервная копия'

c "Запускаем pg_basebackup от имени роли student, указывая формат tar со сжатием:"
eu student "pg_basebackup -c fast -Ft --gzip -D /home/student/tmp/backup"

eu student "ls -l /home/student/tmp/backup"

###############################################################################
h '3. Восстановление из базовой резервной копии'

c 'Основной каталог данных кластера beta'
pgctl_status B
eu student "sudo -u postgres rm -rf $PGDATA_B"

c 'Права на каталог данных в данном случае должны быть лишь у владельца.'
eu student "sudo -u postgres mkdir $PGDATA_B"
eu student "sudo -u postgres chmod 700 $PGDATA_B"

c 'Каталог для табличного пространства ts на сервере, который будет развернут из резервной копии:'

eu student "sudo -u postgres mkdir $H/ts_beta_dir"

c 'Разворачиваем резервную копию:'

e "sudo tar xf /home/student/tmp/backup/base.tar.gz -C $PGDATA_B"
e "sudo tar xf /home/student/tmp/backup/$TSOID.tar.gz -C $H/ts_beta_dir"
e "sudo tar xf /home/student/tmp/backup/pg_wal.tar.gz -C $PGDATA_B/pg_wal"

c 'В каталоге pg_tblspc сейчас пусто:'
e "sudo ls $PGDATA_B/pg_tblspc/"

c 'Символическая ссылка появится при старте сервера в соответствии с файлом tablespace_map (который находился внутри base.tar):'
e "sudo cat $PGDATA_B/tablespace_map"

c 'Изменяем в этом файле путь для табличного пространства:'
e "sudo sed -i 's/ts_dir/ts_beta_dir/' $PGDATA_B/tablespace_map"

###############################################################################
h '4. Запуск и проверка'

c 'Запускаем сервер.'

pgctl_start B

e "sudo ls -l $PGDATA_B/pg_tblspc/"

psql_open B 2 -p 5433 -d $TOPIC_DB
s 2 "\c $TOPIC_DB"
s 2 "SELECT * FROM t;"

###############################################################################
h '5. Удаление базы данных и табличного пространства'

c 'Чтобы удалить БД, надо от нее отключиться.'

s 1 "\c student"
s 1 "DROP DATABASE $TOPIC_DB;"
s 1 "DROP TABLESPACE ts;"
e "sudo rm -rf $H/ts_dir"

c 'И для второго сервера:'

s 2 "\c student"
s 2 "DROP DATABASE $TOPIC_DB;"
s 2 "DROP TABLESPACE ts;"
e "sudo rm -rf $H/ts_beta_dir"

###############################################################################
stop_here
cleanup
demo_end
