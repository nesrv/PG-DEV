#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Подготовка каталога резервных копий и регистрация экземпляра. Режим WAL'

c 'Создаем и подготавливаем каталог копий.'

e 'sudo mkdir /var/probackup'
e 'sudo chown student: /var/probackup'

c 'Инициализируем каталог.'
e "pg_probackup init -B /var/probackup"

c 'Регистрируем экземпляр.'
e "pg_probackup add-instance -B /var/probackup -D /var/lib/pgpro/ent-16 --instance ent-16 --remote-host=localhost --remote-user=postgres"

psql_open A 1

c 'Создадим роль backup и базу данных, к которой будет подключаться эта роль.'
s 1 "CREATE ROLE backup LOGIN REPLICATION PASSWORD 'b@ckUp';"
e "echo 'localhost:5432:$TOPIC_DB:backup:b@ckUp' > ~/.pgpass && chmod 600 ~/.pgpass && cat ~/.pgpass"
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
s 1 "\c $TOPIC_DB"

c 'Запоминаем в настройках конфигурации атрибуты подключения.'
e "pg_probackup set-config -B /var/probackup --instance ent-16 -d $TOPIC_DB -U backup --remote-host=localhost --remote-user=postgres"

c 'Подготовимся к работе в режиме архивирования WAL.'
s 1 "ALTER SYSTEM SET archive_mode = on;"
s 1 "ALTER SYSTEM SET archive_command = '/opt/pgpro/ent-16/bin/pg_probackup archive-push -B /var/probackup --instance=ent-16 --wal-file-path=%p --wal-file-name=%f --remote-host=localhost --remote-user=student';"

c 'Выполним рестарт.'
pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'Проверим работоспособность архивирования WAL.'

CURRENT_WAL=`s_bare 1 "SELECT pg_walfile_name(pg_current_wal_lsn());"`
s 1 "SELECT pg_switch_wal();"
s 1 "CHECKPOINT;"
wait_sql 1 "SELECT last_archived_wal>='${CURRENT_WAL}' FROM pg_catalog.pg_stat_archiver;"

e "pg_probackup show -B /var/probackup --archive"

p

########################################################################
h '2. Подключение и настройка PTRACK'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'ptrack';"
s 1 "ALTER SYSTEM SET client_min_messages TO error;"

c 'Требуется рестарт экземпляра.'

pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'Подключим расширение и зададим значение для параметра ptrack.map_size.'
s 1 "CREATE EXTENSION IF NOT EXISTS ptrack;"

c 'Достаточное значение для ptrack.map_size здесь — 1 Мбайт.'
s 1 "ALTER SYSTEM SET ptrack.map_size = '1MB';"

c 'Снова требуется рестартовать экземпляр.'
pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'Проверим работоспособность PTRACK с помощью вызова функции ptrack_version().'
s 1 "SELECT ptrack_version();"

p

########################################################################
h '3. Сравнение полных и инкрементальных копий'

c 'Полная копия без сжатия.'
e "time pg_probackup backup -B /var/probackup --instance ent-16 -b FULL"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user1"
e "${BINPATH_A}createdb -p 5432 -O user1 db1"

c 'Разностная копия.'
e "time pg_probackup backup -B /var/probackup --instance ent-16 -b DELTA"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user2"
e "${BINPATH_A}createdb -p 5432 -O user2 db2"

c 'Инкрементальная копия измененных страниц по записям в WAL.'
e "time pg_probackup backup -B /var/probackup --instance ent-16 -b PAGE"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user3"
e "${BINPATH_A}createdb -p 5432 -O user3 db3"

c 'Инкрементальная копия измененных страниц по карте изменений PTRACK.'
e "time pg_probackup backup -B /var/probackup --instance ent-16 -b PTRACK"

c 'Сравним полученные результаты.'
e "pg_probackup show -B /var/probackup --instance ent-16"

p

########################################################################
h '4. Сравнение полных и инкрементальных копий со сжатием'

c 'Добавим сжатие в настройки по умолчанию.'
e "pg_probackup set-config -B /var/probackup --instance ent-16 --compress-algorithm=zlib"

c 'Полная копия со сжатием.'
e "time pg_probackup backup -B /var/probackup --instance ent-16 -b FULL"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user4"
e "${BINPATH_A}createdb -p 5432 -O user4 db4"

c 'Разностная копия со сжатием.'
e "time pg_probackup backup -B /var/probackup --instance ent-16 -b DELTA"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user5"
e "${BINPATH_A}createdb -p 5432 -O user5 db5"

c 'Инкрементальная копия измененных страниц по записям в WAL со сжатием.'
e "time pg_probackup backup -B /var/probackup --instance ent-16 -b PAGE"

c 'Небольшая активность...'
e "${BINPATH_A}createuser -p 5432 user6"
e "${BINPATH_A}createdb -p 5432 -O user6 db6"

c 'Инкрементальная копия измененных страниц по карте изменений PTRACK со сжатием.'
e "time pg_probackup backup -B /var/probackup --instance ent-16 -b PTRACK"

c 'Сравним полученные результаты.'
e "pg_probackup show -B /var/probackup --instance ent-16"
ul 'Полные копии занимают значительно больше места, чем инкрементальные.'
ul 'Сжатые копии значительно меньше по размеру, чем несжатые.'
ul 'Использование сжатия лишь незначительно замедлило выполнение резервного копирования.'

p

########################################################################
h '5. Восстановление из сжатой резервной копии'

c 'Останавливаем экземпляр.'
pgctl_stop A

c 'Удаляем содержимое PGDATA.'
e "sudo rm -rf ${PGDATA_A}/*"

e "pg_probackup restore -B /var/probackup --instance ent-16 --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

c 'Стартуем.'

pgctl_start A

psql_open A 1

s 1 "\du"
s 1 "\l"

c "Данные восстановлены."

########################################################################

stop_here
cleanup
