#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Каталог резервных копий и регистрация экземпляра'

c 'Подготавливаем каталог в файловой системе.'

e 'sudo mkdir /var/probackup'
e 'sudo chown student: /var/probackup'

c 'Инициализируем каталог копий.'
e "pg_probackup init -B /var/probackup"

c 'Регистрируем экземпляр.'
e "pg_probackup add-instance -B /var/probackup -D /var/lib/pgpro/ent-16 --instance ent-16"

p

########################################################################
h '2. Роль и база данных для подключения'

psql_open A 1

c 'Создадим роль backup и базу данных, к которой будет подключаться роль backup.'
s 1 'CREATE ROLE backup LOGIN REPLICATION;'
s 1 "CREATE DATABASE $TOPIC_DB OWNER backup;"

c 'Предоставляем права.'
s 1 "\c $TOPIC_DB"
s 1 \
'
BEGIN;
GRANT USAGE ON SCHEMA pg_catalog TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_is_in_recovery() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_start(text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_stop(boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_create_restore_point(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_switch_wal() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_last_wal_replay_lsn() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current_snapshot() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_snapshot_xmax(txid_snapshot) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_checkpoint() TO backup;
COMMIT;
'

c 'Запишем в конфигурацию настройку для выполнения резервной копии от имени пользователя backup.'
e "pg_probackup set-config -B /var/probackup --instance ent-16 -d $TOPIC_DB -U backup"
p

########################################################################
h '3. Полная копия'

c 'Формируем полную копию:'
e "pg_probackup backup -B /var/probackup --instance ent-16 -b FULL --stream"

p

########################################################################
h '4. Разностная копия'

c 'Небольшая активность...'
e "${BINPATH_A}createuser user1"
e "${BINPATH_A}createdb -O user1 db1"

c 'Формируем разностную копию.'
e "pg_probackup backup -B /var/probackup --instance ent-16 -b DELTA --stream"

c 'Проверка.'
e "pg_probackup show -B /var/probackup --instance ent-16"

p

########################################################################
h '5. Восстановление из резервной копии'

c 'Останавливаем экземпляр.'
pgctl_stop A

c 'Удаляем содержимое PGDATA.'
e "sudo rm -rf ${PGDATA_A}/*"

c 'Восстанавливаем с правами root.'
e "sudo pg_probackup restore -B /var/probackup --instance ent-16"

c 'Меняем владельца и группу.'
e "sudo chown -R postgres: ${PGDATA_A}"

c 'Устанавливаем права на чтение для группы, это требуется для потоковой передачи WAL.'
e "sudo chmod -R g+rX ${PGDATA_A}"
e "sudo ls -l ${PGDATA_A}"

c 'Запускаем экземпляр.'
pgctl_start A
psql_open A 1

s 1 "\du"
s 1 "\l"

c "Данные восстановлены."

###############################################################################

stop_here
cleanup
