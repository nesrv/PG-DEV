#!/bin/bash

. ../lib

init 7 # only for users table from bookstore2 database

start_here 5

###############################################################################
h 'Обертка сторонних данных'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Обертка создается при создании расширения:'

s 1 "CREATE EXTENSION postgres_fdw;"

s 1 "\dew"

P 7

###############################################################################
h 'Внешний сервер'

c 'В качестве внешнего сервера выберем базу данных книжного магазина на нашем же локальном сервере.'

s 1 "CREATE SERVER remote_server
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (
    host 'localhost',
    port '5432',
    dbname 'bookstore2'
);"

c 'Обратите внимание, что в параметрах сервера не указывается роль.'

s 1 "\x \des+ \x"

P 9

###############################################################################
h 'Сопоставление ролей'

c 'Настроим соответствие: пусть локальная роль student подключается к внешнему серверу как postgres.'

s 1 "CREATE USER MAPPING FOR student
SERVER remote_server
OPTIONS (
    user 'postgres',
    password 'postgres'
);"

s 1 "\deu+"

c 'Разумеется, можно настраивать несколько соответствий для разных ролей.'

P 11

###############################################################################
h 'Внешние таблицы'

c 'Внешнюю таблицу можно создать явным образом, при необходимости указывая названия объектов, если они отличаются:'

s 1 "CREATE FOREIGN TABLE remote_users (
    id integer OPTIONS (column_name 'user_id') NOT NULL,
    username text NOT NULL,
    email text NOT NULL
)
SERVER remote_server
OPTIONS (
    schema_name 'public',
    table_name 'users'
);"

c 'Можно указать только некоторые ограничения целостности, но в любом случае они не проверяются локально и просто отражают ограничения, накладываемые внешней системой.'

s 1 "\det"

s 1 "SELECT * FROM remote_users WHERE id = 1;"

c 'Как выполняется такой запрос? Иными словами, передается ли предикат внешнему серверу, чтобы он сам выбрал эффективный способ выполнения, или фильтрацией занимается локальный сервер?'

s 1 "EXPLAIN (verbose, costs off)
    SELECT * FROM remote_users WHERE id = 1;"

c 'Планировщик умеет распределять работу между серверами. Также ничто не мешает использовать в одном запросе как внешние, так и локальные данные.'

s 1 "EXPLAIN (costs off)
    SELECT username FROM remote_users
    UNION ALL
    SELECT rolname FROM pg_roles;"

p

c 'Другой способ — не создавать внешние таблицы по одной, а импортировать внешнюю схему (всю или выборочно несколько таблиц), если обертка это позволяет.'

s 1 "CREATE SCHEMA bookstore2;"
s 1 "IMPORT FOREIGN SCHEMA public
    LIMIT TO (users, sessions)
    FROM SERVER remote_server
    INTO bookstore2;"

s 1 "SELECT * FROM bookstore2.users;"

p

c 'Обертка postgres_fdw позволяет и изменять данные:'

s 1 "EXPLAIN (analyze, verbose, costs off)
    UPDATE remote_users
    SET email = 'alice@gmail.com'
    WHERE id = 1;"

P 13

###############################################################################
h 'Соединения и транзакции'

c 'Когда выполнялся запрос к внешней таблице remote_users, обертка открыла соединение и по умолчанию не закрывает его:'

s 1 "SELECT datname, pid FROM pg_stat_activity
WHERE application_name = 'postgres_fdw';"

c 'Завершим обслуживающий процесс...'

FDW_PID=`s_bare 1 "SELECT pid FROM pg_stat_activity WHERE application_name = 'postgres_fdw';"`
s 1 "SELECT pg_terminate_backend($FDW_PID);"

c '...и еще раз обратимся к внешней таблице:'

s 1 "SELECT * FROM remote_users;"

c 'Нам удалось получить данные! Обертка автоматически восстановила подключение, соединение теперь обслуживается другим процессом:'

s 1 "SELECT datname, pid FROM pg_stat_activity
WHERE application_name = 'postgres_fdw';"

c 'Поведение можно изменить, задав атрибут внешнего сервера'
s_fake 1 "keep_connections 'off'"

c 'Тогда обертка будет открывать соединение при каждом обращении к внешней таблице и закрывать его после обращения.'

P 16

###############################################################################
h 'Расширение file_fdw'

c 'Расширение file_fdw позволяет обращаться к любому текстовому файлу и задействует тот же механизм, что и команда COPY. Поэтому для демонстрации мы выгрузим строки из имеющейся таблицы в файл, а затем прочитаем данные из файла.'

s 1 "COPY (SELECT * FROM remote_users)
TO '$H/$VERSION_A/users.txt'
WITH (
    format 'text',
    delimiter '/'
);"

e "cat $H/$VERSION_A/users.txt"

s 1 "CREATE EXTENSION file_fdw;"
s 1 "CREATE SERVER file_server
    FOREIGN DATA WRAPPER file_fdw;"
s 1 "CREATE FOREIGN TABLE file_users (
    id integer,
    username text,
    email text
)
SERVER file_server
OPTIONS (
    filename '$H/$VERSION_A/users.txt',
    format 'text',
    delimiter '/'
);"

s 1 "SELECT * FROM file_users;"

###############################################################################

stop_here
cleanup
demo_end
