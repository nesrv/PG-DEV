#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Подготовка каталога резервного копирования'

c 'Подготавливаем каталог в файловой системе.'

e 'sudo mkdir /var/probackup'
e 'sudo chown student: /var/probackup'

c 'Инициализируем каталог копий.'
e "pg_probackup init -B /var/probackup"

c 'Регистрируем экземпляр.'
e "pg_probackup add-instance -B /var/probackup -D /var/lib/pgpro/ent-16 --instance ent-16"

p

c 'Роль и база данных для подключения.'

psql_open A 1

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
s 1 '\c student'
p

########################################################################
h '2. Настройка журнала сообщений и политики удержания'

c 'Установим политику удержания единственной полной копии и вывод сообщений в журнал.'
e "pg_probackup set-config -B /var/probackup --instance ent-16 -d $TOPIC_DB -U backup --retention-redundancy=1 --log-filename=probackup.log --log-level-file=info --log-level-console=warning"

c 'Проверим настройки.'
e "pg_probackup show-config -B /var/probackup --instance ent-16"
p

########################################################################
h '3. Полная копия'

c 'Формируем полную копию:'
e "pg_probackup backup -B /var/probackup --instance ent-16 -b FULL --stream"

c 'Проверим каталог копий.'
e "pg_probackup show -B /var/probackup --instance ent-16"

c 'Еще одна полная копия.'
e "pg_probackup backup -B /var/probackup --instance ent-16 -b FULL --stream --delete-expired"

c 'Проверим каталог копий — предыдущая копия удалена.'
e "pg_probackup show -B /var/probackup --instance ent-16"

########################################################################

stop_here
cleanup
