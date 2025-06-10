#!/bin/bash

. ../lib
init

start_here 4

###############################################################################
h 'Удаленная работа'

c 'Определим роль backup для резервного копирования и восстановления.'
psql_open A 1
s 1 "CREATE ROLE backup LOGIN REPLICATION PASSWORD 'b@ckUp';"

c 'Создадим файл .pgpass, чтобы не вводить пароль вручную.'
e "cat >~/.pgpass <<EOF
localhost:5432:$TOPIC_DB:backup:b@ckUp
localhost:5432:replication:backup:b@ckUp
EOF"
e 'chmod 600 ~/.pgpass'

c 'Создадим базу данных, к которой будет подключаться роль backup.'
s 1 "CREATE DATABASE $TOPIC_DB OWNER backup;"

c 'Привилегии для роли backup.'

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

c 'Мы будем запускать утилиту локально от имени пользователя ОС student, а агент на удаленном сервере будет обращаться к файлам кластера от имени postgres. Поэтому пользователи student и postgres должны обменяться публичными ключами, сгенерированными без парольной фразы. Это уже сделано в виртуальной машине курса.'

c 'Подготовим локальный каталог копий, владелец файлов — student.'
e 'sudo mkdir /var/probackup'
e 'sudo chown student: /var/probackup'
e "pg_probackup init -B /var/probackup"

c 'Добавим в локальный каталог копий экземпляр БД, работающий на удаленном сервере.'
e "pg_probackup add-instance -B /var/probackup -D /var/lib/pgpro/ent-16 --instance ent-16 --remote-host=localhost --remote-user=postgres"

c 'Чтобы сократить командную строку, сохраним параметры удаленного доступа в конфигурации.'
e "pg_probackup set-config -B /var/probackup --instance ent-16 -d $TOPIC_DB -U backup --remote-host=localhost --remote-user=postgres"

c 'Проверим полученную конфигурацию:'
e "pg_probackup show-config -B /var/probackup --instance ent-16" conf

c 'Теперь выполним полное резервное копирование с удаленного сервера, используя потоковую доставку записей WAL:'
e "pg_probackup backup -B /var/probackup --instance ent-16 -b FULL --stream"

c 'В каталоге резервных копий появилась запись:'
e "pg_probackup show -B /var/probackup --instance ent-16"

###############################################################################
P 6
h 'Архивация WAL'

c 'Подготовим экземпляр к работе с архивацией WAL.'
s 1 "ALTER SYSTEM SET archive_mode = on;"
s 1 "ALTER SYSTEM SET archive_command = 'pg_probackup archive-push -B /var/probackup --instance=ent-16 --wal-file-path=%p --wal-file-name=%f --remote-host=localhost --remote-user=student';"

c 'Экземпляр необходимо перезагрузить.'

pgctl_restart A

psql_open A 1 $TOPIC_DB

c 'Убедимся, что файловая архивация работает и сегменты WAL попадают в каталог копий.'

e "tree --noreport /var/probackup/wal"

CURRENT_WAL=`s_bare 1 "SELECT pg_walfile_name(pg_current_wal_lsn());"`

s 1 "SELECT pg_switch_wal();"
s 1 "CHECKPOINT;"

wait_sql 1 "SELECT last_archived_wal>='${CURRENT_WAL}' FROM pg_catalog.pg_stat_archiver;"

e "tree --noreport /var/probackup/wal"

c 'Информацию об архиве WAL получим средствами pg_probackup:'

e "pg_probackup show -B /var/probackup --archive"

c 'Выполним полное резервное копирование. Поскольку настроена файловая архивация, копировать WAL не нужно, ключ --stream не указываем.'

e "pg_probackup backup -B /var/probackup --instance ent-16 -b FULL"

c 'Проверим каталог резервных копий:'

e "pg_probackup show -B /var/probackup --instance ent-16"

###############################################################################
P 9
h 'Режим PAGE'

c 'Архивацию WAL мы уже настроили. Создадим таблицу и добавим в нее строку.'

s 1 "CREATE TABLE IF NOT EXISTS t1( msg text );"
s 1 "INSERT INTO t1 VALUES ('Проверим режим PAGE.');"

c 'Выполним инкрементальное резервное копирование в режиме PAGE.'

e "pg_probackup backup -B /var/probackup --instance ent-16 -b PAGE"

c 'Проверим каталог резервных копий:'

e "pg_probackup show -B /var/probackup --instance ent-16"

id_page=`pg_probackup show -B /var/probackup --instance ent-16 | awk '$7~/ARCHIVE/ && $6~/PAGE/{print $3}' | head -1`

c 'Попробуем восстановить кластер из этого архива.'

pgctl_stop A

c 'Удаляем содержимое PGDATA.'

e "sudo rm -rf ${PGDATA_A}/*"

c 'Восстанавливаем. К команде добавим ключи для автоматического формирования restore_command.'
e "pg_probackup restore -B /var/probackup --instance ent-16 -i ${id_page} --archive-host=localhost --archive-user=student"

c 'Стартуем Postgres Pro Enterprise.'

pgctl_start A

psql_open A 1 $TOPIC_DB

wait_sql 1 "select not pg_is_in_recovery();"

s 1 "SELECT * FROM t1;"

c 'Проверим пишущую транзакцию.'

s 1 "INSERT INTO t1 VALUES ('Проверим пишущую транзакцию.');"

s 1 "SELECT * FROM t1;"

c 'После удаленного восстановления данные не потеряны, экземпляр работоспособен.'

###############################################################################
P 11
h 'Частичное восстановление'

c "Для частичного восстановления роль backup должна иметь право на чтение pg_catalog.pg_database в базе данных $TOPIC_DB."

s 1 "\c $TOPIC_DB"

s 1 'GRANT SELECT ON TABLE pg_catalog.pg_database TO backup;'

c 'Для демонстрации частичного восстановления создадим базу данных и таблицу.'

s 1 'CREATE DATABASE fatedb;'

s 1 '\c fatedb'

s 1 "CREATE TABLE prof_fate (button text);"
s 1 "INSERT INTO prof_fate VALUES ('Push the Button, Max!');"

c 'Выполним инкрементальное копирование, созданная база попадет в резервную копию.'

e "pg_probackup backup -B /var/probackup --instance ent-16 -b PAGE"

c 'Проверим каталог резервных копий:'

e "pg_probackup show -B /var/probackup --instance ent-16"

id_page=`pg_probackup show -B /var/probackup --instance ent-16 | awk '$7~/ARCHIVE/ && $6~/PAGE/{print $3}' | head -1`

c 'Команда merge объединяет полную копию со всеми дочерними инкрементальными:'

e "pg_probackup merge -B /var/probackup --instance ent-16 -i ${id_page}"

c 'Останавливаем экземпляр.'

pgctl_stop A

c 'Удаляем содержимое PGDATA.'

e "sudo rm -rf ${PGDATA_A}/*"

c 'Сначала восстановим кластер целиком.'

e "pg_probackup restore -B /var/probackup --instance ent-16 -i ${id_page} --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

c 'Стартуем.'

pgctl_start A
psql_open A 1 $TOPIC_DB

wait_sql 1 "select not pg_is_in_recovery();"

c 'Восстановились все базы данных:'

s 1 "\l"

c 'Таблица в базе fatedb тоже восстановлена:'

s 1 "\c fatedb"
s 1 "SELECT * FROM prof_fate;"

c 'Теперь восстановим все базы данных кластера кроме fatedb.'

pgctl_stop A

c 'Снова удаляем содержимое PGDATA.'

e "sudo rm -rf ${PGDATA_A}/*"

c 'Добавим к командной строке ключ --db-exclude, чтобы база fatedb не восстанавливалась.'

e "pg_probackup restore -B /var/probackup --instance ent-16 -i ${id_page} --db-exclude=fatedb --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

c 'Стартуем.'

pgctl_start A
psql_open A 1 $TOPIC_DB

wait_sql 1 "select not pg_is_in_recovery();"

c 'База данных fatedb есть в списке:'
s 1  "\l"

fatedb_oid=`psql -Aqtc "SELECT oid FROM pg_database WHERE datname='fatedb';"`

c 'Однако подключиться к ней нельзя:'
e 'psql fatedb'

c 'В подкаталоге PGDATA этой базы только пустые файлы.'
e "sudo du -ch $PGDATA/base/${fatedb_oid} | tail -n 1"

###############################################################################
P 13
h 'Инкрементальное восстановление'

pgctl_stop A

c 'Инкрементальное восстановление включается параметром -I с указанием режима.'
c 'Выполним инкрементальное восстановление в режиме CHECKSUM:'

e "pg_probackup restore -B /var/probackup --instance ent-16 -i ${id_page} -I CHECKSUM --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

pgctl_start A

psql_open A 1 $TOPIC_DB
wait_sql 1 "select not pg_is_in_recovery();"


c 'База данных fatedb должна быть восстановлена, и запрос к таблице в этой базе должен выполниться успешно.'

s 1 '\c fatedb'
s 1 "SELECT * FROM prof_fate;"
s 1 "\c $TOPIC_DB"

###############################################################################
P 15
h 'Восстановление на момент в прошлом'

c 'Пока в каталоге лишь две полные копии.'
e "pg_probackup show -B /var/probackup --instance ent-16"

full_arch_lsn=`pg_probackup show -B /var/probackup --instance ent-16 | awk '$7~/ARCHIVE/ && $6~/FULL/{print $15}' | head -1`
id_full=`pg_probackup show -B /var/probackup --instance ent-16 | awk '$7~/ARCHIVE/ && $6~/FULL/{print $3}' | head -1`

c 'Добавим еще одну запись к таблице и выполним инкрементальное копирование.'

s 1 "SELECT * FROM t1;"
s 1 "INSERT INTO t1 VALUES( 'Запись попадет в инкрементальную копию.' );"

e "pg_probackup backup -B /var/probackup --instance ent-16 -b PAGE"

c 'Проверим каталог резервных копий:'

e "pg_probackup show -B /var/probackup --instance ent-16"

c 'Используя команду validate, можно проверить возможность восстановления до заданной целевой точки. В нашем случае необходимо указать идентификатор копии.'
c "Проверим, можно ли восстановиться до заданной позиции WAL:"

e "pg_probackup validate -B /var/probackup --instance ent-16 -i ${id_full} --recovery-target-lsn=${full_arch_lsn}"

c "Выполним восстановление из копии ${id_full} до LSN ${full_arch_lsn}."

pgctl_stop A

c 'Удаляем содержимое PGDATA и запускаем команду restore:'

e "sudo rm -rf ${PGDATA_A}/*"

e "pg_probackup restore -B /var/probackup --instance ent-16 -i ${id_full} --recovery-target-lsn=${full_arch_lsn} --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

c 'Стартуем.'

pgctl_start A

psql_open A 1 $TOPIC_DB

s 1 "SELECT * FROM t1;"

c 'Восстановление приостановлено после достижения целевой точки:'

s 1 "SELECT pg_is_wal_replay_paused();"

c 'Завершим восстановление.'

s 1 "SELECT pg_wal_replay_resume();"
wait_sql 1 "select not pg_is_in_recovery();"
s 1 "SELECT pg_is_in_recovery();"

c "Данные восстановлены на момент, соответствующий LSN ${full_arch_lsn}."

c 'Выполним полное копирование с архивированием WAL, так как текущий экземпляр восстановлен до точки времени в прошлом.'

e "pg_probackup backup -B /var/probackup --instance ent-16 -b FULL"

###############################################################################

stop_here
cleanup
demo_end
