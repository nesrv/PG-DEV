#!/bin/bash

. ../lib

init

start_here

###############################################################################
h 'Статистика обращений к таблице'

c 'Создаем базу данных и таблицу:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE t(n numeric);'
s 1 'INSERT INTO t SELECT 1 FROM generate_series(1,1000);'
s 1 'DELETE FROM t;'

c 'Проверяем статистику обращений.'

sleep 1
DUMMY=`s_bare 1 "SELECT 1;"`
sleep 1
s 1 "SELECT * FROM pg_stat_all_tables WHERE relid = 't'::regclass \gx"

c 'Мы вставили 1000 строк (n_tup_ins = 1000), удалили 1000 строк (n_tup_del = 1000).'
c 'После этого не осталось активных версий строк (n_live_tup = 0), все 1000 строк не актуальны на текущий момент (n_dead_tup = 1000).'

c 'Выполним очистку.'

s 1 'VACUUM;'

wait_sql 1 "SELECT n_dead_tup = 0 FROM pg_stat_all_tables WHERE relid = 't'::regclass;"
s 1 "SELECT * FROM pg_stat_all_tables WHERE relid = 't'::regclass \gx"

c 'Неактуальные версии строк убраны при очистке (n_dead_tup = 0), очистка обрабатывала таблицу один раз (vacuum_count = 1).'

###############################################################################
h '2. Взаимоблокировка'

s 1 'INSERT INTO t VALUES (1),(2);'

c 'Одна транзакция блокирует первую строку таблицы...'
psql_open A 2
s 2 "\c $TOPIC_DB"
s 2 'BEGIN;'
s 2 'UPDATE t SET n = 10 WHERE n = 1;'

c 'Затем другая транзакция блокирует вторую строку...'
psql_open A 3
s 3 "\c $TOPIC_DB"
s 3 'BEGIN;'
s 3 'UPDATE t SET n = 200 WHERE n = 2;'

c 'Теперь первая транзакция пытается изменить вторую строку и ждет ее освобождения...'
ss 2 'UPDATE t SET n = 20 WHERE n = 2;'
sleep 1

c 'А вторая транзакция пытается изменить первую строку...'
ss 3 'UPDATE t SET n = 100 WHERE n = 1;'
sleep 1

c '...и происходит взаимоблокировка. Сервер обрывает одну из транзакций:'
r 3

c 'Другая транзакция разблокируется:'
r 2

c 'Проверим информацию в журнале сообщений:'
e "sudo tail -n 8 $LOG_A"

###############################################################################
stop_here
cleanup
demo_end
