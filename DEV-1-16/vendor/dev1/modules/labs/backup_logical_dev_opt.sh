#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Открытие результата запроса в LibreOffice'

c 'Создаем таблицу.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE TABLE t(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    s text
);"
s 1 "INSERT INTO t(s) VALUES ('foo'), ('bar'), ('baz');"

c 'Выгружаем содержимое таблицы в csv-файл:'
s 1 "\copy t TO PROGRAM 'cat > t.csv' WITH (format csv);"

c 'Если вместо \copy использовать SQL-команду COPY, программа будет запущена на сервере СУБД, что, конечно, неправильно.'

open-file "/home/$OSUSER/t.csv"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
