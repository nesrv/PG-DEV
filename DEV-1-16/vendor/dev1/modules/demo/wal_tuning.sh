#!/bin/bash

. ../lib

init

start_here 5

###############################################################################

h 'Уровни журнала'

c 'Используем новую базу данных.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Уровень журнала по умолчанию — replica.'

s 1 'SHOW wal_level;'

c 'Посмотрим, как записывается в журнал команда CREATE TABLE AS SELECT.'

s 1 "SELECT pg_current_wal_insert_lsn();"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")
s 1 "SELECT pg_walfile_name('$START_LSN');"

s 1 'CREATE TABLE t_wal(n) AS SELECT 1 from generate_series(1,1000);'

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")


c 'Объем журнала:'

s 1 "SELECT '$END_LSN'::pg_lsn - '$START_LSN'::pg_lsn;"

c 'Помимо изменений системного каталога, в журнал попадают записи:'
ul 'CREATE — создание файла отношения;'
ul 'INSERT+INIT — вставка строк в таблицу;'
ul 'COMMIT — фиксация транзакции.'

export SEGMENTS=$(s_bare 1 "SELECT pg_walfile_name('$START_LSN')||' '||pg_walfile_name('$END_LSN');")
e "sudo ${BINPATH_A}pg_waldump -p $PGDATA_A/pg_wal -s $START_LSN -e $END_LSN $SEGMENTS | grep 'CREATE\|INSERT+INIT\|COMMIT'" pgwaldump

c 'На уровне replica журнал содержит все изменения данных, что позволяет применить их к физической резервной копии или к реплике.'

p

c 'Установим для журнала уровень minimal (при этом придется также задать нулевое значение параметра max_wal_senders и перезапустить сервер).'

s 1 'ALTER SYSTEM SET wal_level = minimal;'
s 1 'ALTER SYSTEM SET max_wal_senders = 0;'

pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'Посмотрим, как теперь записывается в журнал команда CREATE TABLE AS SELECT.'

s 1 'DROP TABLE t_wal;'

s 1 "SELECT pg_current_wal_insert_lsn();"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")
s 1 "SELECT pg_walfile_name('$START_LSN');"

s 1 'CREATE TABLE t_wal(n) AS SELECT 1 from generate_series(1,1000);'

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")


c 'Объем журнала уменьшился:'

s 1 "SELECT '$END_LSN'::pg_lsn - '$START_LSN'::pg_lsn;"

c 'В журнале нет записей INSERT+INIT:'

export SEGMENTS=$(s_bare 1 "SELECT pg_walfile_name('$START_LSN')||' '||pg_walfile_name('$END_LSN');")
e "sudo ${BINPATH_A}pg_waldump -p $PGDATA_A/pg_wal -s $START_LSN -e $END_LSN $SEGMENTS | grep 'CREATE\|INSERT+INIT\|COMMIT'" pgwaldump

c 'На уровне minimal изменения, выполненные операторами CREATE TABLE AS SELECT, TRUNCATE и некоторыми другими не журналируются. Эти операторы всегда сами выполняют синхронизацию, обеспечивая долговечность. А журнал содержит только записи, необходимые для восстановления после сбоя.'

p

c 'Вернем уровень по умолчанию (replica).'

s 1 'ALTER SYSTEM RESET wal_level;'
s 1 'ALTER SYSTEM RESET max_wal_senders;'

pgctl_restart A
psql_open A 1 $TOPIC_DB

###############################################################################
P 10
h 'Контрольные суммы'

c 'Создадим еще одну таблицу:'

s 1 "CREATE TABLE t(id integer);"
s 1 "INSERT INTO t VALUES (1),(2),(3);"

c 'Вот файл, в котором находятся данные:'

s 1 "SELECT pg_relation_filepath('t');"
export FNAME=$(s_bare 1 "SELECT pg_relation_filepath('t');")

c 'Остановим сервер и поменяем несколько байтов в странице (сотрем из заголовка LSN последней журнальной записи).'

pgctl_stop A

e "sudo dd if=/dev/zero of=$PGDATA_A/$FNAME oflag=dsync conv=notrunc bs=1 count=8"

c 'Можно было бы и не останавливать сервер. Достаточно, чтобы:'
ul 'страница записалась на диск и была вытеснена из кеша;'
ul 'произошло повреждение;'
ul 'страница была прочитана с диска.'

p

c 'Теперь запускаем сервер.'

pgctl_start A
psql_open A 1 $TOPIC_DB

c 'Попробуем прочитать таблицу:'

s 1 "SELECT * FROM t;"

c 'Параметр ignore_checksum_failure позволяет попытаться все-таки прочитать таблицу, хоть и с риском получить искаженные данные (например, если нет резервной копии):'

s 1 "SET ignore_checksum_failure = on;"
s 1 "SELECT * FROM t;"

###############################################################################
P 15
h 'Влияние синхронной фиксации на производительность'

c 'Режим, включенный по умолчанию, — синхронная фиксация.'

s 1 "SHOW synchronous_commit;"

c 'Запустим простой тест производительности с помощью утилиты pgbench. Для этого сначала инициализируем необходимые таблицы...'

e "pgbench -i $TOPIC_DB"

c '...а также сбросим статистику о работе журнала предзаписи:'
s 1 "SELECT pg_stat_reset_shared('wal');"

c 'Запускаем тест на 10 секунд.'

e "pgbench -P 1 -T 10 $TOPIC_DB"

c 'В результатах pgbench нас интересует число транзакций или скорость (tps), а в данных представления pg_stat_wal - количество операций записи и синхронизации журнала:'
s 1 "SELECT wal_records, wal_bytes, wal_write, wal_sync FROM pg_stat_wal;"

p

c 'Теперь установим асинхронный режим.'

s 1 "ALTER SYSTEM SET synchronous_commit = off;"
s 1 "SELECT pg_reload_conf();"

c 'Сбросим накопленные данные.'
s 1 "SELECT pg_stat_reset_shared('wal');"

c 'И снова запускаем тест.'

e "pgbench -P 1 -T 10 $TOPIC_DB"
s 1 "SELECT wal_records, wal_bytes, wal_write, wal_sync FROM pg_stat_wal;"

c 'Кроме повышения tps, мы видим и саму причину повышения производительности: количество операций записи и синхронизации журнала значительно уменьшились.'

c 'Разумеется, на реальной системе соотношение может быть другим, но видно, что в асинхронном режиме производительность существенно выше.'

###############################################################################

stop_here
cleanup
demo_end
