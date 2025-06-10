#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Размер журнальных записей'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Запомним начальную позицию в журнале:'

s 1 "SELECT pg_current_wal_insert_lsn();"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'Создадим таблицу и добавим строки:'

s 1 "CREATE TABLE t(
  id integer PRIMARY KEY,
  s text
);"
s 1 "INSERT INTO t VALUES (1, 'A'), (2, 'B'), (3, 'C');"

c 'Запомним конечную позицию:'

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'Размер журнальных записей:'

s 1 "SELECT '$END_LSN'::pg_lsn - '$START_LSN'::pg_lsn;"

###############################################################################
h '2. Состав журнальных записей'

c 'Журнальный файл:'

s 1 "SELECT pg_walfile_name('$START_LSN');"

export START_SEG=$(s_bare 1 "SELECT pg_walfile_name('$START_LSN');")

c 'Понадобится расширение pg_walinspect:'

s 1 'CREATE EXTENSION pg_walinspect;'

c 'Смотрим записи:'

s 1 "SELECT start_lsn, xid, resource_manager, record_type,
regexp_match(block_ref, 'rel (\d+\/\d+/\d+) fork (\w+) blk (\w+)') AS bref,
substr(description, 1, 50) AS descr
FROM pg_get_wal_records_info('$START_LSN', '$END_LSN');"

c 'Вначале (до первой операции COMMIT) происходит активная работа с таблицами и индексами системного каталога. За счет этого размер записей и получился существенно больше, чем в демонстрации.'

###############################################################################
h '3. Восстановление после сбоя'

c 'Обновляем строки:'

s 1 "UPDATE t SET s = 'FOO';"

s 1 "BEGIN;"
s 1 "UPDATE t SET s = 'BAR'; -- не фиксируем транзакцию"

c 'Прерываем основной серверный процесс.'

kill_postgres A
pgctl_status A

c 'Запускаем сервер.'

pgctl_start A

c 'Проверяем изменения:'

psql_open A 1 $TOPIC_DB
s 1 "SELECT * FROM t;"

c 'Журнал сообщений:'

e "tail -n 6 $LOG_A"

###############################################################################

stop_here
cleanup
