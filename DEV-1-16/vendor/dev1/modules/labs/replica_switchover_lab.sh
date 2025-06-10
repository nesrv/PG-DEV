#!/bin/bash

. ../lib
init

start_here
###############################################################################
h '1. Настройка репликации без архива'

c 'Настраиваем репликацию.'

c 'Создаем автономную резервную копию, предварительно создав слот.'

# Начиная с 10 версии, по умолчанию pg_basebackup использует --wal-method=stream
e "pg_basebackup --checkpoint=fast --pgdata=/home/$OSUSER/tmp/backup -R --slot=replica --create-slot"
e "sudo cat /home/$OSUSER/tmp/backup/postgresql.auto.conf"

c 'Выкладываем резервную копию в каталог PGDATA будущей реплики'
pgctl_status B
e "sudo rm -rf $PGDATA_B"
e "sudo mv /home/$OSUSER/tmp/backup $PGDATA_B"
e "sudo chown -R postgres:postgres $PGDATA_B"

c 'Запускаем сервер в режиме реплики.'
pgctl_start B

c 'Проверим настройки. Выполним несколько команд на мастере:'

s 1 'CREATE DATABASE replica_switchover;'
s 1 '\c replica_switchover'
s 1 'CREATE TABLE test(s text);'
s 1 "INSERT INTO test VALUES ('Привет, мир!');"
sleep 2

c 'Проверим реплику:'
psql_open B 2 -p 5433
wait_db 2 replica_switchover
s 2 "\c replica_switchover"
wait_sql 2 "SELECT true FROM pg_tables WHERE tablename='test';"
wait_sql 2 "SELECT count(*)=1 FROM test;"
s 2 'SELECT * FROM test;'

###############################################################################
h '2. Сбой основного сервера и переход на реплику'

psql_close 1
kill_postgres A
sleep 1

pgctl_promote B
wait_sql 2 "SELECT not pg_is_in_recovery();"

###############################################################################
h '3. Возвращение в строй бывшего мастера'

c 'Создаем автономную резервную копию, предварительно создав слот.'

c 'Удалим конфигурационный файл, иначе basebackup его скопирует и допишет параметры.'
e "sudo rm -rf $PGDATA_B/postgresql.auto.conf"
e "rm -rf /home/$OSUSER/tmp/backup"
e "pg_basebackup --checkpoint=fast -p 5433 --pgdata=/home/$OSUSER/tmp/backup -R --slot=replica --create-slot"

c 'Параметры конфигурации и сигнальный файл подготовлены утилитой pg_basebackup:'

e "sudo cat /home/$OSUSER/tmp/backup/postgresql.auto.conf"
e "ls -l /home/$OSUSER/tmp/backup/standby.signal"

c 'Выкладываем копию на бывший мастер и запускаем новую реплику.'
e "sudo rm -rf $PGDATA_A"
e "sudo mv /home/$OSUSER/tmp/backup $PGDATA_A"
e "sudo chown -R postgres:postgres $PGDATA_A"
pgctl_start A

c 'Слот репликации инициализировался и используется:'
s 2 'SELECT * FROM pg_replication_slots \gx'

c 'Проверим еще:'
s 2 "INSERT INTO test VALUES ('Я - бывшая реплика (новый мастер).');"

psql_open A 1 -p 5432 -d replica_switchover
wait_sql 1 "SELECT count(*)=2 FROM test;"
s 1 'SELECT * FROM test;'

###############################################################################
h '4. Переключение на новую реплику'

pgctl_promote A
s 1 "select pg_is_in_recovery();"

c 'В итоге прежний мастер снова стал основным сервером.'

###############################################################################
stop_here
cleanup
demo_end
