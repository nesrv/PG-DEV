#!/bin/bash

. ../lib
init

start_here
###############################################################################
h '1. Архивная копия.'

psql_open A 1 -U postgres

c 'Установим достаточное значение параметра wal_keep_size.'
s 1 'ALTER SYSTEM SET wal_keep_size = 32;'
s 1 'SELECT pg_reload_conf();'

c 'Создадим БД и таблицу.'
s 1 "\c - student"
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB postgres"
s 1 'CREATE TABLE t(s text);'
s 1 "INSERT INTO t VALUES ('Перед обычным копированием.');"

c "Выполним копирование в каталог /home/student/tmp/bkp"
eu student "pg_basebackup -D /home/student/tmp/bkp -c fast -Ft -Xf --gzip"

p

###############################################################################
h '2. Копирование вручную.'

c 'Остановим гамму и опустошим ее каталог данных.'
pgctl_stop C
eu student "sudo -u postgres rm -rf $PGDATA_C"
eu student "sudo -u postgres mkdir $PGDATA_C"
eu student "sudo -u postgres chmod 700 $PGDATA_C"

c 'Восстановим данные из архивной копии.'
eu student "sudo tar xf /home/student/tmp/bkp/base.tar.gz -C $PGDATA_C"

c 'Запустим режим копирования.'
s 1 "SELECT pg_backup_start(label => 'ByHand', fast => true);"
c 'Аргумент fast задан для выполнения быстрой контрольной точки.'

c 'Добавим строку в таблицу.'
s 1 "INSERT INTO t VALUES ('Изменение во время копирования вручную.');"

c 'Скопируем произошедшие в файловой системе изменения в каталоге альфы в каталог данных гаммы.'
eu student "sudo -u postgres rsync -av $PGDATA_A/ $PGDATA_C/" pgsql

c 'Завершим режим резервного копирования.'
s 1 "SELECT * FROM pg_backup_stop(wait_for_archive => true);"

c 'Удалим в каталоге данных гаммы лишние файлы.'
eu student "sudo -u postgres rm -f $PGDATA_C/postmaster.{pid,opts}"

c 'Скопируем с альфы все сегменты WAL, отсутствующие на гамме.'
eu student "sudo -u postgres rsync -av $PGDATA_A/pg_wal/ $PGDATA_C/pg_wal/"

c 'Запустим гамму и проверим наличие данных.'
pgctl_start C

psql_open C 2 -p 5434 -d $TOPIC_DB -U postgres
s 2 "SELECT * FROM t;"

###############################################################################
h '3. Очистка.'

s 1 "\c $OSUSER"
s 1 "DROP DATABASE $TOPIC_DB;"
e "rm -rf tmp/bkp"

pgctl_stop C

###############################################################################
stop_here
cleanup
demo_end
