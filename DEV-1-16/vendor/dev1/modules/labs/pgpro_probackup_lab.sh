#!/bin/bash

. ../lib
init
start_here

###############################################################################
h '1.Подготовка каталога резервных копий и регистрация экземпляра.'

c 'Создаем и подготавливаем каталог копий.'

e 'sudo mkdir /var/probackup'
e 'sudo chown student:student /var/probackup'

c 'Инициализируем каталог.'
e "${BINPATH_A}pg_probackup init -B /var/probackup"

c 'Регистрируем экземпляр.'
e "${BINPATH_A}pg_probackup add-instance -B /var/probackup -D /var/lib/pgpro/ent-13 --instance ent-13 --remote-host=localhost --remote-user=postgres"

p

########################################################################
h '2.Регистрируем роль и создаем базу данных для подключения.'

psql_open A 1

c 'Создадим  роль backup и базу данных, к которой будет подключаться роль backup.'
s 1 'CREATE ROLE backup LOGIN REPLICATION;'
s 1 'CREATE DATABASE backup OWNER backup;'

c 'Предоставляем права.'
s 1 '\c backup'
s 1 \
'
BEGIN;
GRANT USAGE ON SCHEMA pg_catalog TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_is_in_recovery() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_start_backup(text, boolean, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_stop_backup(boolean, boolean) TO backup;
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

c 'Запоминаем в настройках конфигурации атрибуты подключения.'
e "${BINPATH_A}pg_probackup set-config -B /var/probackup --instance ent-13 -d backup -U backup --remote-host=localhost --remote-user=postgres"

p

########################################################################
h '3.Подготовка экземпляра в режиме архивирования WAL.'

c 'Подготовимся к работе в режиме архивирования WAL.'
s 1 "ALTER SYSTEM SET archive_mode = on;"
s 1 "ALTER SYSTEM SET archive_command = '/opt/pgpro/ent-13/bin/pg_probackup archive-push -B /var/probackup --instance=ent-13 --wal-file-path=%p --wal-file-name=%f --remote-host=localhost --remote-user=student';"

c 'Выполним перезагрузку.'
psql_close 1
pgctl_restart A
psql_open A 1

c 'Проверим работоспособность архивирования WAL.'
s 1 "SELECT pg_switch_wal();"
s 1 "CHECKPOINT;"
e "${BINPATH_A}pg_probackup show -B /var/probackup --archive"

p

########################################################################
h '4.Подключение и настройка PTRACK.'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'ptrack';"
s 1 "ALTER SYSTEM SET client_min_messages TO error;"

c 'Требуется перезагрузка экземпляра.'

psql_close 1
pgctl_restart A
psql_open A 1

c 'Подключим расширение. И зададим значение для параметра ptrack.map_size'
s 1 "\c backup"
s 1 "CREATE EXTENSION IF NOT EXISTS ptrack;"

c 'Достаточное значение для ptrack.map_size здесь - 1МБ.'
s 1 "ALTER SYSTEM SET ptrack.map_size = '1MB';"

c 'Снова требуется перезагрузка экземпляра.'
psql_close 1
pgctl_restart A
psql_open A 1

c 'Проверьте работоспособность PTRACK с помощью вызова функции ptrack_version().'
s 1 "\c backup"
s 1 "SELECT ptrack_version();"

psql_close 1

p

########################################################################
h '5.Сравнение полных и инекрементальных копий.'

c 'Полная копия без компресии.'
e "time ${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b FULL"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user1"
e "${BINPATH_A}createdb -p5432 -O user1 user1"

c 'Разностная копия.'
e "time ${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b DELTA"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user2"
e "${BINPATH_A}createdb -p5432 -O user2 user2"

c 'Инкрементальная копия измененных страниц по записям в WAL.'
e "time ${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PAGE"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user3"
e "${BINPATH_A}createdb -p5432 -O user3 user3"

c 'Инкрементальная копия измененных страниц по карте изменений PTRACK.'
e "time ${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PTRACK"

c 'Сравним полученные результаты.'
e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

p

########################################################################
h '6.Сравнение полных и инекрементальных копий со сжатием.'

c 'Добавим компрессию в настройки по умолчанию.'
e "${BINPATH_A}pg_probackup set-config -B /var/probackup --instance ent-13 --compress-algorithm=zlib"

c 'Полная копия с компрессией.'
e "time ${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b FULL"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user4"
e "${BINPATH_A}createdb -p5432 -O user4 user4"

c 'Разностная копия с компрессией.'
e "time ${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b DELTA"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user5"
e "${BINPATH_A}createdb -p5432 -O user5 user5"

c 'Инкрементальная копия измененных страниц по записям в WAL с компрессией.'
e "time ${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PAGE"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user6"
e "${BINPATH_A}createdb -p5432 -O user6 user6"

c 'Инкрементальная копия измененных страниц по карте изменений PTRACK с компрессией.'
e "time ${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PTRACK"

c 'Сравним полученные результаты.'
e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

p

########################################################################
h '7.Восстановление из сжатой резервной копии.'

c 'Останавливаем экземпляр.'
pgctl_stop A

c 'Удаляем содержимое PGDATA.'
eu postgres "rm -rf ${PGDATA_A}/*"

e "${BINPATH_A}pg_probackup restore -B /var/probackup --instance ent-13 --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

c 'Стартуем.'

pgctl_start A

psql_open A 1

s 1 "\du"
s 1 "\l"

c "Данные восстановлены."

psql_close 1

p

########################################################################
stop_here
cleanup
demo_end
