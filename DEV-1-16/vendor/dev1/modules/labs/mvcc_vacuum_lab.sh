#!/bin/bash

. ../lib

init

psql_open A 2

start_here

###############################################################################
h '1. Сканирование индексов при очистке'

c 'Создадим таблицу с данными и индекс. Параметр autovacuum_enabled выключен, чтобы не срабатывала автоматическая очистка.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 'CREATE TABLE t(id integer) WITH (autovacuum_enabled = off);'
s 1 "INSERT INTO t SELECT gen.id FROM generate_series(1,1_000_000) gen(id);"
s 1 'CREATE INDEX t_id ON t(id);'

c 'Уменьшаем размер памяти, выделяемой под массив идентификаторов:'

s 1 "ALTER SYSTEM SET maintenance_work_mem = '1MB';"
s 1 "SELECT pg_reload_conf();"

c 'Обновляем все строки:'

s 1 "UPDATE t SET id = id + 1;"

c 'Запускаем очистку. Заодно через небольшое время в другом сеансе обратимся к pg_stat_progress_vacuum.'

ss 1 "VACUUM VERBOSE t;"

sleep 0.5
si 2 "\c $TOPIC_DB"
si 2 'SELECT * FROM pg_stat_progress_vacuum \gx'

r 1 

c 'Восстановим значение измененного параметра.'

s 1 "ALTER SYSTEM RESET maintenance_work_mem;"
s 1 "SELECT pg_reload_conf();"

p

###############################################################################
h '2. Очистка большого количества строк'

c 'Текущий размер файла данных:'

s 1 "SELECT pg_size_pretty(pg_table_size('t'));"

c 'Удалим 90% случайных строк. Случайность важна, чтобы в каждой странице остались какие-нибудь неудаленные строки — в противном случае очистка имеет шанс уменьшить размер файла.'

s 1 'DELETE FROM t WHERE random() < 0.9;'

c 'Объем после очистки:'

s 1 "VACUUM t;"
s 1 "SELECT pg_size_pretty(pg_table_size('t'));"

c 'Объем не изменился.'

p

###############################################################################
h '3. Полная очистка большого количества строк'

c 'Заново наполним таблицу.'

s 1 'TRUNCATE t;'
s 1 "INSERT INTO t SELECT gen.id FROM generate_series(1,1_000_000) gen(id);"

c 'Текущий размер файла данных:'

s 1 "SELECT pg_size_pretty(pg_table_size('t'));"

c 'Обратите внимание, что в прошлый раз размер был примерно в два раза больше. Вторая половина была занята версиями строк, которые создала команда UPDATE.'

c 'Объем после удаления и полной очистки:'

s 1 'DELETE FROM t WHERE random() < 0.9;'
s 1 "VACUUM FULL t;"
s 1 "SELECT pg_size_pretty(pg_table_size('t'));"

c 'Объем уменьшился на 90%.'

###############################################################################

stop_here
cleanup
