#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. База данных'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

###############################################################################
h '2. Размер БД'

s 1 "SELECT pg_size_pretty(pg_database_size('$TOPIC_DB'));"

c 'Запомним значение в переменной psql:'

s 1 "SELECT pg_database_size('$TOPIC_DB') AS oldsize \gset"

###############################################################################
h '3. Схемы и таблицы'

s 1 "CREATE SCHEMA app;"
s 1 "CREATE SCHEMA $USER;"

c 'В какой схеме будут созданы таблицы без явного указания?'
s 1 "SELECT current_schema();"

c "Таблицы для схемы $USER:"

s 1 "CREATE TABLE a(s text);"
s 1 "INSERT INTO a VALUES ('${USER}');"
s 1 "CREATE TABLE b(s text);"
s 1 "INSERT INTO b VALUES ('${USER}');"

c "Таблицы для схемы app:"

s 1 "CREATE TABLE app.a(s text);"
s 1 "INSERT INTO app.a VALUES ('app');"
s 1 "CREATE TABLE app.c(s text);"
s 1 "INSERT INTO app.c VALUES ('app');"

###############################################################################
h '4. Изменение размера БД'

s 1 "SELECT pg_size_pretty(pg_database_size('$TOPIC_DB'));"
s 1 "SELECT pg_database_size('$TOPIC_DB') AS newsize \gset"

c 'Размер изменился на:'

s 1 "SELECT pg_size_pretty(:newsize::bigint - :oldsize::bigint);"

###############################################################################
h '5. Путь поиска'

c "С текущими настройками пути поиска видны таблицы только схемы $USER:"

s 1 'SELECT * FROM a;'
s 1 'SELECT * FROM b;'
s 1 'SELECT * FROM c;'

c 'Изменим путь поиска:'

s 1 "ALTER DATABASE $TOPIC_DB SET search_path = \"\$user\",app,public;"

s 1 '\c'
s 1 'SHOW search_path;'

c "Теперь видны таблицы из обеих схем, но приоритет остается за $USER:"

s 1 'SELECT * FROM a;'
s 1 'SELECT * FROM b;'
s 1 'SELECT * FROM c;'

###############################################################################
stop_here
cleanup
demo_end
