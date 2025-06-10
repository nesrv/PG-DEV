#!/bin/bash

. ../lib
init

start_here 6
###############################################################################
h 'Настройка потоковой репликации'

c 'Поскольку в нашей конфигурации не будет архива журнала предзаписи, важно на всех этапах использовать слот репликации — иначе при определенной задержке мастер может успеть удалить необходимые сегменты и весь процесс придется повторять с самого начала.'
c 'Создаем слот:'
s 1 "SELECT pg_create_physical_replication_slot('replica');"

c 'Посмотрим на созданный слот:'
s 1 'SELECT * FROM pg_replication_slots \gx'

c 'Вначале слот не инициализирован (restart_lsn и wal_status пустые).'

p

c 'Разрешение на подключение в pg_hba.conf есть, все необходимые настройки есть по умолчанию:'
s 1 "\dconfig wal_level|max_wal_senders|max_replication_slots"

c 'Поместим автономную резервную копию в каталог данных беты, используя созданный слот. Копию расположим в подготовленном каталоге. С ключом -R утилита создает файлы, необходимые для будущей реплики.'
pgctl_stop B
e "sudo -u postgres rm -rf $PGDATA_B"
e "sudo -u postgres pg_basebackup -D $PGDATA_B -R --slot=replica"

c 'Снова проверим слот:'
s 1 'SELECT * FROM pg_replication_slots \gx'
c 'После выполнения резервной копии слот инициализировался, и мастер теперь хранит все файлы журнала с начала копирования (restart_lsn, wal_status).'

c 'Сравните со строкой в backup_label:'
e "sudo -u postgres head -n 1 $PGDATA_B/backup_label"

c 'Файл postgresql.auto.conf был подготовлен утилитой pg_basebackup, поскольку мы указали ключ -R. Он содержит информацию для подключения к мастеру (primary_conninfo) и имя слота репликации (primary_slot_name):'
e "sudo -u postgres cat $PGDATA_B/postgresql.auto.conf"

p

c 'По умолчанию реплика будет «горячей», то есть сможет выполнять запросы во время восстановления. Если такая возможность не нужна, реплику можно сделать «теплой» (hot_standby = off).'
c 'Утилита также создала сигнальный файл standby.signal, наличие которого указывает серверу войти в режим постоянного восстановления.'
e "sudo -u postgres ls -l $PGDATA_B/standby.signal"

c 'Журнальные записи, необходимые для восстановления согласованности, реплика получит от мастера по протоколу репликации. Далее она войдет в режим непрерывного восстановления и продолжит получать и проигрывать поток записей.'

pgctl_start B

P 10

###############################################################################
h 'Процессы реплики'

c 'Сравним процессы на мастере:'
e 'ps f -C postgres | grep alpha'

c 'И на реплике:'
e 'ps f -C postgres | grep beta'

r_startup=$(psql -p 5433 -Atqc "select pid from pg_stat_activity where backend_type = 'startup'")
r_walrece=$(psql -p 5433 -Atqc "select pid from pg_stat_activity where backend_type = 'walreceiver'")
m_walsend=$(psql -Atqc "select pid from pg_stat_activity where backend_type = 'walsender'")

c 'На реплике процесс процессы wal writer и autovacuum launcher отсутствуют, а процесс wal receiver принимает поток журнальных записей.'
e "ps fp $r_walrece"

c 'Процесс startup на реплике применяет изменения:'
e "ps fp $r_startup"

c 'На мастере добавился процесс wal sender, обслуживающий подключение по протоколу репликации:'
e "ps fp $m_walsend"

P 12

###############################################################################
h 'Использование реплики'

c 'Выполним несколько команд на мастере:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE test(s text);'
s 1 "INSERT INTO test VALUES ('Привет, мир!');"

c 'Проверим реплику:'

psql_open B 2 -p 5433
wait_db 2 $TOPIC_DB
s 2 "\c $TOPIC_DB"

wait_sql 2 "select true from pg_tables where tablename='test';"
wait_sql 2 "select count(*)=1 from test;"

s 2 'SELECT * FROM test;'

c 'При этом изменения на реплике не допускаются:'
s 2 "INSERT INTO test VALUES ('Replica');"

c 'Вообще реплику от мастера можно отличить с помощью функции:'
s 2 "SELECT pg_is_in_recovery();"

P 15

###############################################################################
h 'Мониторинг репликации'

c 'Состояние репликации можно смотреть в специальном представлении на мастере. Чтобы пользователь получил доступ к этой информации, ему должна быть выдана роль pg_read_all_stats (или он должен быть суперпользователем).'
s 1 '\drg student|pg_monitor'
c 'Роль pg_monitor входит в роль pg_read_all_stats и наследует ее привилегии.'
s 1 'SELECT * FROM pg_stat_replication \gx'
c 'Обратите внимание на поля *_lsn (и *_lag) — они показывают отставание реплики на разных этапах. Сейчас все позиции совпадают, отставание нулевое.'

p

c 'Теперь вставим в таблицу большое количество строк, чтобы увидеть репликацию в процессе работы.'
si 1 "INSERT INTO test SELECT 'Just a line' FROM generate_series(1,1000000);"
si 1 'SELECT *, pg_current_wal_lsn() from pg_stat_replication \gx'
c 'Видно, что возникла небольшая задержка.'

wait_sql 2 "select count(*)=1000001 from test;"

c 'Проверим реплику:'
s 2 'SELECT count(*) FROM test;'
c 'Все строки успешно доставлены.'

c 'И еще раз проверим состояние репликации:'
s 1 'SELECT *, pg_current_wal_lsn() from pg_stat_replication \gx'
c 'Все позиции выровнялись.'

P 18

###############################################################################
h 'Влияние слота репликации'

c 'Остановим реплику.'
pgctl_stop B

c 'Ограничим размер WAL двумя сегментами.'
s 1 "\c - postgres"
s 1 "ALTER SYSTEM SET min_wal_size='32MB';"
s 1 "ALTER SYSTEM SET max_wal_size='32MB';"
s 1 "SELECT pg_reload_conf();"
s 1 "\c - student"

c 'Слот неактивен, но помнит номер последней записи, полученной репликой:'
s 1 "SELECT active, restart_lsn, wal_status FROM pg_replication_slots \gx"

c 'Вставим еще строки в таблицу.'
s 1 "INSERT INTO test SELECT 'Just a line' FROM generate_series(1,1000000);"

c 'Номер LSN в слоте не изменился:'
s 1 "SELECT active, restart_lsn, wal_status FROM pg_replication_slots \gx"

c 'Выполним контрольную точку, которая должна очистить журнал, поскольку его размер превышает допустимый.'
s 1 "CHECKPOINT;"

c 'Каков теперь размер журнала?'
s 1 "SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();"
c 'Контрольная точка не удалила сегменты — их удерживает слот, несмотря на превышение лимита. Если оставить слот без присмотра, дисковое пространство может быть исчерпано.'

c 'Скорее всего, бесперебойная работа основного сервера важнее, чем синхронизация реплики. Чтобы предотвратить разрастание журнала, можно ограничить объем, удерживаемый слотом:'
s 1 "\c - postgres"
s 1 "ALTER SYSTEM SET max_slot_wal_keep_size='16MB';"
s 1 "SELECT pg_reload_conf();"
s 1 "\c - student"
s 1 "CHECKPOINT;"

c 'Теперь журнал очищается контрольной точкой:'
s 1 "SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();"

c 'Но слот уже не обеспечивает наличие записей WAL (wal_status=lost):'
s 1 "SELECT active, restart_lsn, wal_status FROM pg_replication_slots \gx"

c 'А реплика не может синхронизироваться:'
pgctl_start B

e "sudo tail -n 2 $LOG_B"
c 'Для синхронизации реплики в таких случаях можно воспользоваться архивом, задав параметр restore_command. Если это невозможно, придется заново настроить репликацию, повторив формирование базовой копии.'

###############################################################################
stop_here
cleanup
demo_end
