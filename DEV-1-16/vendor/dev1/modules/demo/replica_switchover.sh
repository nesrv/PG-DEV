#!/bin/bash

. ../lib
init

start_here 5
################################################################################
h 'Настройка потоковой репликации'

c 'Настроим реплику так же, как делали в предыдущей теме, а потом перейдем на нее.'

c 'Создаем автономную резервную копию, попросив утилиту создать слот и необходимые файлы (postgresql.auto.conf с настройками и standby.signal).'
e "pg_basebackup --checkpoint=fast --pgdata=/home/$OSUSER/tmp/backup -R --slot=replica --create-slot"

c 'Выкладываем копию в каталог PGDATA сервера beta:'
pgctl_status B
e "sudo rm -rf $PGDATA_B"
e "sudo mv /home/$OSUSER/tmp/backup $PGDATA_B"
e "sudo chown -R postgres:postgres $PGDATA_B"

c 'Запускаем реплику:'
pgctl_start B

c 'Проверим настроенную репликацию. Выполним несколько команд на мастере:'

s 1 'CREATE DATABASE replica_switchover;'
s 1 '\c replica_switchover'
s 1 'CREATE TABLE test(s text);'
s 1 "INSERT INTO test VALUES ('Привет, мир!');"

c 'Проверим реплику:'

psql_open B 2 -p 5433
wait_db 2 replica_switchover
s 2 "\c replica_switchover"

wait_sql 2 "select true from pg_tables where tablename='test';"
wait_sql 2 "select count(*)=1 from test;"

s 2 'SELECT * FROM test;'

p

###############################################################################
h 'Переход на реплику'

c 'Сейчас сервер beta является репликой (находится в режиме восстановления):'

s 2 'SELECT pg_is_in_recovery();'

c 'Повышаем реплику. В версии 13 появилась функция pg_promote(), которая выполняет то же действие.'

pgctl_promote B
wait_sql 2 "SELECT not pg_is_in_recovery();"

c 'Теперь бывшая реплика стала полноценным экземпляром.'

s 2 'SELECT pg_is_in_recovery();'

c 'Мы можем изменять данные:'

s 2 "INSERT INTO test VALUES ('Я - бывшая реплика (новый мастер).');"

P 11

###############################################################################
h 'Утилита pg_rewind'

c 'Между тем сервер alpha еще не выключен и тоже может изменять данные:'

s 1 "INSERT INTO test VALUES ('Die hard');"

c 'В реальности такой ситуации необходимо всячески избегать, поскольку теперь непонятно, какому серверу верить. Придется либо полностью потерять изменения на одном из серверов, либо придумывать, как объединить данные.'

c 'Наш выбор — потерять изменения, сделанные на первом сервере.'

c 'Мы планируем использовать утилиту pg_rewind, поэтому убедимся, что включены контрольные суммы на страницах данных:'

s 1 "SHOW data_checksums;"

c 'Этот параметр служит только для информации; изменить его нельзя — подсчет контрольных сумм задается при инициализации кластера или утилитой pg_checksums на остановленном сервере.'

c 'Остановим целевой сервер (alpha) некорректно.'

sleep-ni 3
kill_postgres A
sleep-ni 1

p

c 'Создадим на сервере-источнике (beta) слот для будущей реплики:'

s 2 "SELECT pg_create_physical_replication_slot('replica');"

c 'И проверим, что параметр full_page_writes включен:'

s 2 "SHOW full_page_writes;"

p

c 'Если целевой сервер не был остановлен корректно, утилита сначала запустит его в монопольном режиме и остановит с выполнением контрольной точки. Для запуска требуется наличие файла postgresql.conf в PGDATA.'

eu postgres "touch $PGDATA_A/postgresql.conf"

c 'В ключах утилиты pg_rewind надо указать каталог PGDATA целевого сервера и способ обращения к серверу-источнику: либо подключение от имени суперпользователя (если сервер работает), либо местоположение его каталога PGDATA (если он выключен).'

eu postgres "${BINPATH_A}pg_rewind -D $PGDATA_A --source-server='user=postgres port=5433' -R -P"

c 'В результате работы pg_rewind «откатывает» файлы данных на ближайшую контрольную точку до того момента, как пути серверов разошлись, а также создает файл backup_label, который обеспечивает применение нужных журналов для завершения восстановления.'
c 'Заглянем в backup_label:'

e "sudo cat $PGDATA_A/backup_label"

c 'Ключом -R мы попросили утилиту создать сигнальный файл standby.signal и задать в конфигурационном файле строку соединения.'

e "sudo ls -l $PGDATA_A/standby.signal"

e "sudo cat $PGDATA_A/postgresql.auto.conf"

c 'Утилита добавляет строку для primary_conninfo в конец существующего файла конфигурации, поэтому остальные настройки (primary_slot_name) продолжат действовать.'
p

c 'Можно стартовать новую реплику.'

pgctl_start A

c 'Слот репликации инициализировался и используется:'

wait_sql 2 "SELECT active FROM pg_replication_slots WHERE slot_name='replica';"
s 2 'SELECT * FROM pg_replication_slots \gx'

c 'Данные, измененные на новом мастере, получены:'

psql_open A 1 -p 5432 -d replica_switchover
s 1 'SELECT * FROM test;'

c 'Проверим еще:'

s 2 "INSERT INTO test VALUES ('Еще строка с нового мастера.');"

wait_sql 1 "SELECT count(*)=3 FROM test;"
s 1 'SELECT * FROM test;'

c 'Таким образом, два сервера поменялись ролями.'

P 14

###############################################################################
h 'Проблемы с файловым архивом'

c 'Сейчас beta — основной сервер, а alpha — реплика. Настроим на обоих файловую архивацию в общий архив.'

psql_open B 2 -p 5433 -d replica_switchover

e "sudo mkdir $H/archive"
e "sudo chown postgres:postgres $H/archive"
s 2 '\c - postgres'
s 2 'ALTER SYSTEM SET archive_mode = on;'
s 2 "ALTER SYSTEM SET archive_command = 'test ! -f $H/archive/%f && cp %p $H/archive/%f';"
s 1 '\c - postgres'
s 1 'ALTER SYSTEM SET archive_mode = on;'
s 1 "ALTER SYSTEM SET archive_command = 'test ! -f $H/archive/%f && cp %p $H/archive/%f';"

psql_close 2
psql_close 1

c 'Перезапускаем оба сервера.'
pgctl_restart B
pgctl_restart A

c 'Текущий сегмент журнала:'

psql_open B 2 -p 5433 -d replica_switchover -U postgres
s 2 'SELECT pg_walfile_name(pg_current_wal_lsn());'

# Запоминаем текущий сегмент
CURRENT_WAL=`s_bare 2 "SELECT pg_walfile_name(pg_current_wal_lsn());"`

c 'Принудительно переключим сегмент WAL, вызвав функцию pg_switch_wal. Чтобы переключение произошло, нужно гарантировать, что текущий и следующий сегменты содержат какие-либо записи.'

s 2 "SELECT pg_switch_wal();
INSERT INTO test SELECT now();"

# Ждём архивацию
wait_sql 2 "SELECT last_archived_wal>='${CURRENT_WAL}' FROM pg_stat_archiver;"

c 'Теперь записывается следующий сегмент, а предыдущий попал в архив:'
s 2 'SELECT
	pg_walfile_name(pg_current_wal_lsn()) current_wal,
	last_archived_wal,
	last_failed_wal
FROM pg_stat_archiver;'

c 'Теперь представим, что возникли трудности с архивацией. Причиной может быть, например, заполнение диска или проблемы с сетевым соединением, а мы смоделируем их, возвращая статус 1 из команды архивации.'

s 2 "ALTER SYSTEM SET archive_command = 'exit 1';
SELECT pg_reload_conf();"
wait_param 2 'archive_command' 'exit 1'
sleep-ni 1 # чтобы archiver уж точно увидел параметр

c 'Опять переключим сегмент WAL.'

# Запоминаем текущий сегмент
CURRENT_WAL=`s_bare 2 "SELECT pg_walfile_name(pg_current_wal_lsn());"`

s 2 "SELECT pg_switch_wal();
INSERT INTO test SELECT now();"

# Ждём архивацию
wait_sql 2 "SELECT last_failed_wal>='${CURRENT_WAL}' FROM pg_stat_archiver;"

c 'Сегмент не архивируется.'
s 2 'SELECT
	pg_walfile_name(pg_current_wal_lsn()) current_wal,
	last_archived_wal,
	last_failed_wal
FROM pg_stat_archiver;'

c 'Процесс archiver будет продолжать попытки, но безуспешно.'
sleep-ni 1 # чтобы в логе было несколько попыток
e "tail -n 4 $LOG_B"

c 'Alpha в режиме реплики не выполняла архивацию, а после перехода не будет архивировать пропущенный сегмент.'
c 'Остановим сервер beta, переключаемся на alpha.'

psql_close 2
kill_postgres B
pgctl_promote A

c 'Еще раз принудительно переключим сегмент, теперь уже на alpha.'
psql_open A 1 -U postgres -d replica_switchover

s 1 "SELECT pg_switch_wal();
INSERT INTO test SELECT now();"

c 'Что с архивом?'
e "ls -l $H/archive"

c "Сегмент ${CURRENT_WAL} отсутствует, архив теперь непригоден для восстановления и репликации."

P 16
###############################################################################

h 'Архивация с реплики'

c 'Чтобы при переключении на реплику архив не пострадал, на реплике нужно использовать значение archive_mode = always. При этом команда архивации должна корректно обрабатывать одновременную запись сегмента мастером и репликой.'
p

c 'Восстановим архивацию на сервере alpha. Файл будет копироваться только при отсутствии в архиве, а наличие файла в архиве не будет считаться ошибкой.'

s 1 "ALTER SYSTEM SET archive_command = 'test -f $H/archive/%f || cp %p $H/archive/%f';
SELECT pg_reload_conf();"

c 'Добавим слот для реплики.'

s 1 "SELECT pg_create_physical_replication_slot('replica');"

c 'Теперь настроим beta как реплику с архивацией в режиме always.'

e "cat << EOF | sudo -u postgres tee $PGDATA_B/postgresql.auto.conf
primary_conninfo='user=student port=5432'
primary_slot_name='replica'
archive_mode='always'
archive_command='test -f $H/archive/%f || cp %p $H/archive/%f'
EOF"

c 'Стартуем реплику.'
eu postgres "touch $PGDATA_B/standby.signal"
pgctl_start B

p

psql_open A 1 -U postgres -d replica_switchover

c 'Повторим опыт. Переключаем сегмент:'

# Запоминаем текущий сегмент
CURRENT_WAL=`s_bare 1 "SELECT pg_walfile_name(pg_current_wal_lsn());"`

s 1 "SELECT pg_switch_wal();
INSERT INTO test SELECT now();"

# Ждём архивацию на мастере (альфе)
wait_sql 1 "SELECT last_archived_wal>='${CURRENT_WAL}' FROM pg_stat_archiver;"

c 'Проверяем состояние архивации:'
s 1 'SELECT
	pg_walfile_name(pg_current_wal_lsn()) current_wal,
	last_archived_wal,
	last_failed_wal
FROM pg_stat_archiver;'

c 'Заполненный сегмент попал в архив.'
p

c 'На сервере alpha возникли проблемы с архивацией, команда возвращает 1:'
s 1 "ALTER SYSTEM SET archive_command = 'exit 1';
SELECT pg_reload_conf();"
wait_param 1 'archive_command' 'exit 1'
sleep-ni 1 # чтобы archiver уж точно увидел параметр

c 'Alpha продолжает генерировать сегменты WAL.'

# Запоминаем текущий сегмент
CURRENT_WAL=`s_bare 1 "SELECT pg_walfile_name(pg_current_wal_lsn());"`

s 1 "SELECT pg_switch_wal();
INSERT INTO test SELECT now();"

# Ждём архивацию на мастере (альфе)
wait_sql 1 "SELECT last_failed_wal>='${CURRENT_WAL}' FROM pg_stat_archiver;"

c 'Но основной сервер их не архивирует:'
s 1 'SELECT
	pg_walfile_name(pg_current_wal_lsn()) current_wal,
	last_archived_wal,
	last_failed_wal
FROM pg_stat_archiver;'

# Ждём синхронизацию реплики (беты) подольше
wait_replica_sync 1 B 60

c 'Однако архивация с реплики срабатывает и сегмент оказывается в архиве:'
# pg_stat_archiver на реплике не показывает факт архивации, на всякий случай ждём ещё пару секунд
sleep-ni 2
e "ls -l $H/archive"

c 'Выполняем переключение на реплику.'
psql_close 1
kill_postgres A
pgctl_promote B

c 'Beta стала основным сервером и генерирует файлы WAL.'
psql_open B 2 -p 5433 -U postgres -d replica_switchover

# Запоминаем текущий сегмент
CURRENT_WAL=`s_bare 2 "SELECT pg_walfile_name(pg_current_wal_lsn());"`

s 2 "SELECT pg_switch_wal();
INSERT INTO test SELECT now();"

# Ждём архивацию на мастере (бете)
wait_sql 2 "SELECT last_archived_wal>='${CURRENT_WAL}' FROM pg_stat_archiver;"

c 'Еще раз заглянем в архив:'
e "ls -l $H/archive"

c 'В архиве появились файлы реплики, пропусков в нем нет, проблема решена.'

###############################################################################
stop_here
cleanup
demo_end
