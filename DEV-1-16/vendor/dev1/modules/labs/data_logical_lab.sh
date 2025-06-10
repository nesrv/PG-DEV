#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. База данных, схемы, таблицы'

c 'Создаем базу данных:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Схемы:'

s 1 "CREATE SCHEMA $OSUSER;"
s 1 "CREATE SCHEMA app;"

c "Таблицы для схемы $OSUSER:"

s 1 "CREATE TABLE a(s text);"
s 1 "INSERT INTO a VALUES ('"$OSUSER"');"
s 1 "CREATE TABLE b(s text);"
s 1 "INSERT INTO b VALUES ('"$OSUSER"');"

c "Таблицы для схемы app:"

s 1 "CREATE TABLE app.a(s text);"
s 1 "INSERT INTO app.a VALUES ('app');"
s 1 "CREATE TABLE app.c(s text);"
s 1 "INSERT INTO app.c VALUES ('app');"

###############################################################################
h '2. Описание схем и таблиц'

c 'Описание схем:'

s 1 '\dn'

c 'Описание таблиц:'

s 1 '\dt '$OSUSER'.*'
s 1 '\dt app.*'

###############################################################################
h '3. Путь поиска'

c "С текущими настройками пути поиска видны только таблицы, находящиеся в схеме $OSUSER:"

s 1 'SELECT * FROM a;'
s 1 'SELECT * FROM b;'
s 1 'SELECT * FROM c;'

c 'Изменим путь поиска на уровне базы.'

s 1 "ALTER DATABASE $TOPIC_DB SET search_path = \"\$user\",app,public;"

s 1 '\c'
s 1 'SHOW search_path;'

c "Теперь видны таблицы из обеих схем, но приоритет остается за $OSUSER:"

s 1 'SELECT * FROM a;'
s 1 'SELECT * FROM b;'
s 1 'SELECT * FROM c;'

s 1 "select usename, application_name from pg_stat_activity where datname = '$TOPIC_DB';"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
