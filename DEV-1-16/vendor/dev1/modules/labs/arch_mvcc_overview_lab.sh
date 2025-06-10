#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
psql_open A 2
s 2 "\c $TOPIC_DB"

start_here

###############################################################################
h '1. Уровень изоляции Read Committed'

c 'Создаем таблицу:'

s 1 "CREATE TABLE t(n integer);"
s 1 "INSERT INTO t VALUES (42);"

c 'Запрос из первой транзакции (по умолчанию используется уровень изоляции Read Committed):'

s 1 "BEGIN;"
s 1 "SELECT * FROM t;"

c 'Удаляем строку во второй транзакции и фиксируем изменения:'

s 2 "DELETE FROM t;"

c "Повторим запрос:"

s 1 "SELECT * FROM t;"

c 'Первая транзакция видит произошедшие изменения: строка удалена.'

s 1 "COMMIT;"

###############################################################################
h '2. Уровень изоляции Repeatable Read'

c 'Вернем строку:'

s 1 "INSERT INTO t VALUES (42);"

c 'Запрос из первой транзакции:'

s 1 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
s 1 "SELECT * FROM t;"

c 'Удаляем строку во второй транзакции и фиксируем изменения:'

s 2 "DELETE FROM t;"

c "Повторим запрос:"

s 1 "SELECT * FROM t;"

c 'На этом уровне изоляции первая транзакция не видит изменений: для нее строка по-прежнему существует.'

s 1 "COMMIT;"

###############################################################################

stop_here
s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

cleanup
