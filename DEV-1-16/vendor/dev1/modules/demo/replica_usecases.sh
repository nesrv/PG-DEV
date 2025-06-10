#!/bin/bash

. ../lib
init

start_here 8
###############################################################################
h 'Мастер и две физические реплики'

c 'Настроим конфигурацию с двумя репликами.'

c 'Создадим автономную резервную копию первого сервера, одновременно создав слот.'

e "pg_basebackup --checkpoint=fast --pgdata=/home/$OSUSER/tmp/backup -R --create-slot --slot=beta"

c 'Поскольку третий сервер при старте начнет применять записи WAL с той же позиции, что и второй, можно дублировать слот:'

s 1 "\c - postgres"
s 1 "SELECT pg_copy_physical_replication_slot('beta','gamma');"
s 1 "\c - $OSUSER"

c 'Выложим автономную копию в каталоги PG_DATA второго и третьего серверов:'

pgctl_status B
e "sudo rm -rf $PGDATA_B"
e "sudo cp -r /home/$OSUSER/tmp/backup $PGDATA_B"
e "sudo chown -R postgres:postgres $PGDATA_B"

pgctl_status C
e "sudo rm -rf $PGDATA_C"
e "sudo cp -r /home/$OSUSER/tmp/backup $PGDATA_C"
e "sudo chown -R postgres:postgres $PGDATA_C"

c 'В конфигурации третьего сервера укажем слот gamma:'

e "sudo sed 's/beta/gamma/g' -i $PGDATA_C/postgresql.auto.conf"
e "sudo tail -n 1 $PGDATA_C/postgresql.auto.conf"

c 'Запускаем обе реплики:'

pgctl_start B
pgctl_start C

c 'Слоты инициализировались:'

s 1 "SELECT slot_name, active_pid, restart_lsn FROM pg_replication_slots;"

c 'Проверяем.'

s 1 "CREATE DATABASE replica_usecases;"
s 1 "\c replica_usecases"
s 1 "CREATE TABLE revenue(city text, amount numeric);"

psql_open B 2 -p 5433
psql_open C 3 -p 5434

wait_db 2 "replica_usecases"
wait_db 3 "replica_usecases"

s 2 "\c replica_usecases"
s 3 "\c replica_usecases"

wait_sql 2 "SELECT true FROM pg_tables WHERE tablename='revenue';"
wait_sql 3 "SELECT true FROM pg_tables WHERE tablename='revenue';"

s 2 "\d revenue"
s 3 "\d revenue"

c 'Мы настроили две реплики одного мастера на основе одной базовой копии.'

P 14

###############################################################################
h 'Консолидация с помощью логической репликации'

c 'Выведем обе настроенные ранее реплики из режима восстановления и настроим консолидацию данных.'

s 2 "\c - postgres"
s 2 "SELECT pg_promote(), pg_is_in_recovery();"
s 3 "\c - postgres"
s 3 "SELECT pg_promote(), pg_is_in_recovery();"

c 'Для логической репликации нужно повысить уровень WAL (потребуется рестарт).'

s 2 "ALTER SYSTEM SET wal_level = 'logical';"
s 3 "ALTER SYSTEM SET wal_level = 'logical';"

pgctl_restart B
pgctl_restart C

c 'Публикуем таблицу на втором и третьем серверах:'

psql_open B 2 -p 5433 -d replica_usecases
s 2 "CREATE PUBLICATION revenue FOR TABLE revenue;"

psql_open C 3 -p 5434 -d replica_usecases
s 3 "CREATE PUBLICATION revenue FOR TABLE revenue;"

c 'Первый сервер подписывается на обе публикации:'

s 1 "\c - postgres"
s 1 "CREATE SUBSCRIPTION msk CONNECTION 'port=5433 dbname=replica_usecases' PUBLICATION revenue;"
s 1 "CREATE SUBSCRIPTION spb CONNECTION 'port=5434 dbname=replica_usecases' PUBLICATION revenue;"
s 1 "\c - $OSUSER"

c 'В филиалах кипит работа:'

s 2 "INSERT INTO revenue
  SELECT 'Москва', random()*1e6 FROM generate_series(1,70);"
s 3 "INSERT INTO revenue
  SELECT 'Санкт-Петербург', random()*1e6 FROM generate_series(1,10);"

c 'А центральный офис видит работу всей компании (подождем несколько секунд, чтобы сработала репликация):'

wait_sql 1 "SELECT count(*)=80 FROM revenue;"
s 1 "SELECT city, sum(amount) FROM revenue GROUP BY city;"

###############################################################################
stop_here
cleanup
demo_end
