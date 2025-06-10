#!/bin/bash

. ../lib
init

start_here
###############################################################################
h '1. Настройка репликации между первым и вторым серверами'

c 'Сначала создадим базу данных.'

psql_open A 1
s 1 'CREATE DATABASE replica_usecases;'
s 1 '\c replica_usecases'

c 'Создаем слот и автономную резервную копию.'
e "pg_basebackup --checkpoint=fast --pgdata=/home/$OSUSER/tmp/backup -R --create-slot --slot=replica"

c 'Файлы postgresql.auto.conf и standby.signal подготовлены утилитой pg_basebackup.'
e "cat /home/$OSUSER/tmp/backup/postgresql.auto.conf"
e "ls -l /home/$OSUSER/tmp/backup/standby.signal"

c 'Выкладываем копию и запускаем реплику:'
pgctl_status B
e "sudo rm -rf $PGDATA_B"
e "sudo mv /home/$OSUSER/tmp/backup $PGDATA_B"
e "sudo chown -R postgres:postgres $PGDATA_B"
pgctl_start B

###############################################################################
h '2. Настройка репликации между вторым и третьим серверами'

psql_open B 2 -p 5433 -d replica_usecases

c 'Создадим автономную резервную копию со второго сервера, чтобы показать возможность выполнения резервного копирования с реплики. Слот создается утилитой.'
e "pg_basebackup --checkpoint=fast -p 5433 --pgdata=/home/$OSUSER/tmp/backup -R --create-slot --slot=replica"

c 'Файл postgresql.auto.conf подготовлен утилитой pg_basebackup, добавляем задержку воспроизведения:'
e "echo \"recovery_min_apply_delay = '10s'\" | tee -a /home/$OSUSER/tmp/backup/postgresql.auto.conf"

c 'Вот что получилось:'
e "cat /home/$OSUSER/tmp/backup/postgresql.auto.conf"

c 'Копию записываем в каталог PGDATA третьего сервера.'
pgctl_status C
e "sudo rm -rf $PGDATA_C"
e "sudo mv /home/$OSUSER/tmp/backup $PGDATA_C"
e "sudo chown -R postgres:postgres $PGDATA_C"

c 'Запускаем сервер gamma.'
pgctl_start C

###############################################################################
h '3. Проверка работы'

c 'На первом сервере создадим таблицу и проверим, что она появилась сначала на одной реплике, а через 10 секунд — и на другой.'
s 1 'CREATE TABLE test(s text);'
s 1 "INSERT INTO test VALUES ('Привет, мир!');"

wait_sql 2 "SELECT true FROM pg_tables WHERE tablename='test';"
wait_sql 2 "SELECT count(*)=1 FROM test;"
s 2 'SELECT * FROM test;'

c 'Проверяем другую реплику:'
psql_open C 3 -p 5434 -d replica_usecases
s 3 'SELECT * FROM test;'

c 'Таблицы пока нет. Подождем 10 секунд...'
sleep 10
wait_sql 3 "SELECT true FROM pg_tables WHERE tablename='test';"
wait_sql 3 "SELECT count(*)=1 FROM test;"
s 3 'SELECT * FROM test;'

c 'Таблица появилась.'

###############################################################################
h '4. Переход на второй сервер'

c 'Текущая линия времени на третьем сервере.'
s 3 'SELECT received_tli FROM pg_stat_wal_receiver;'

c 'При «повышении» второго сервера номер ветви увеличится на единицу, и процедура восстановления на третьем сервере пойдет по новой ветви благодаря значению по умолчанию:'
s 3 "SELECT setting, boot_val FROM pg_settings WHERE name = 'recovery_target_timeline';"

psql_close 1
pgctl_stop A
pgctl_promote B
wait_sql 2 "SELECT not pg_is_in_recovery();"

c 'Линия времени на третьем сервере сменилась.'
s 3 'SELECT received_tli FROM pg_stat_wal_receiver;'

###############################################################################
h '5. Проверка работы'

c 'На втором сервере добавим в таблицу строки и проверим, что они появились на третьем сервере через 10 секунд.'
s 2 "INSERT INTO test VALUES ('После перехода на второй сервер');"
sleep 2

c 'Проверяем:'
s 3 'SELECT * FROM test;'

c 'Данных пока нет. Ждем 10 секунд...'
sleep 10
s 3 'SELECT * FROM test;'

c 'Данные появились.'

###############################################################################
stop_here
cleanup
demo_end
