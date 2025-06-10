#!/bin/bash

. ../lib

init

pgctl_start R

start_here ...

###############################################################################
h '1. Сравнение таблиц в разных базах'

c 'Таблица в первой базе данных:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE TABLE test (
    s text
);"
s 1 "INSERT INTO test VALUES ('foo'),('bar'),('baz');"

c 'И во второй (расположим ее на втором сервере в БД postgres):'

psql_open R 2 -U postgres -d postgres

s 2 "CREATE TABLE test (
    s text
);"
s 2 "INSERT INTO test VALUES ('foo'),('bar');"

c 'Создаем стороннюю таблицу для доступа к таблице во второй базе данных:'

s 1 "CREATE EXTENSION postgres_fdw;"
s 1 "CREATE SERVER remote_server
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (
    host 'localhost',
    port '5433',
    dbname 'postgres'
);"

c 'На втором сервере используем роль postgres:'

s 1 "CREATE USER MAPPING FOR student
SERVER remote_server
OPTIONS (
    user 'postgres'  -- пароль не нужен, аутентификация trust
);"
s 1 "CREATE FOREIGN TABLE test2 (
    s text
)
SERVER remote_server
OPTIONS (
    schema_name 'public',
    table_name 'test'
);"

c 'Сравниваем:'

s 1 "SELECT * FROM test
EXCEPT
SELECT * FROM test2;"

p

c 'С помощью расширения dblink задачу можно решить следующим образом:'

s 1 "CREATE EXTENSION dblink;"
s 1 "SELECT * FROM test
EXCEPT
SELECT * FROM dblink(
    'host=localhost port=5433 dbname=postgres user=postgres',
    'SELECT * FROM test'
) AS (s text);"

c 'В этом случае подготовительные действия практически не требуются, но сам запрос выглядит сложнее.'

p

###############################################################################
h '2. Проверка работы postgres_fdw'

c 'На втором сервере настроим журнал сообщений так, чтобы в него попадала информация о подключениях и отключениях, а также о выполняемых командах.'

s 2 "ALTER SYSTEM SET log_connections = on;"
s 2 "ALTER SYSTEM SET log_disconnections = on;"
s 2 "ALTER SYSTEM SET log_statement = 'all';"
s 2 "SELECT pg_reload_conf();"

c 'Начнем новое соединение и локальную транзакцию Read Committed.'

psql_close 1
psql_open A 1 $TOPIC_DB
s 1 "BEGIN;"

c 'Обращаемся к сторонней таблице:'

s 1 "SELECT * FROM test2;"

c 'В журнале второго сервера видим:'
ul 'установлено новое соединение;'
ul 'в нем выставлены некоторые параметры;'
ul 'начата транзакция с уровнем изоляции Repeatable Read;'
ul 'с помощью курсора прочитаны записи из таблицы test.'

e "sudo tail -n 12 $LOG_R"

c 'Завершаем локальную транзакцию.'

s 1 "COMMIT;"

c 'В журнале видим, что удаленная транзакция также завершена:'

e  "sudo tail -n 1 $LOG_R"

c 'Завершаем сеанс.'

psql_close 1

c 'В этот момент завершается и соединение с удаленным узлом:'

e "sudo tail -n 2 $LOG_R"

c 'Журнал сообщений можно использовать, чтобы разобраться, как работа внешних средств выглядит с точки зрения СУБД.'

###############################################################################

stop_here
cleanup
