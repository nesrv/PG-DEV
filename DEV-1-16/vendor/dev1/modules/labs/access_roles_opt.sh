#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Роли и таблица'

PSQL_PROMPT1='student=# '
s 1 'CREATE ROLE alice WITH LOGIN;'
s 1 'CREATE ROLE bob WITH LOGIN;'

s 1 'CREATE DATABASE access_roles OWNER alice;'

s 1 '\c access_roles alice'
PSQL_PROMPT1='alice=> '

s 1 'CREATE TABLE test (id integer);'

###############################################################################
h '2. Добавление владельца таблицы'

c 'Чтобы Боб мог изменять структуру таблицы, он должен стать ее владельцем. Для этого можно включить роль bob в роль alice. В этой ситуации это может сделать лишь суперпользователь.'

s 1 "\c - student"
PSQL_PROMPT1='student=# '
s 1 "GRANT alice TO bob;"
s 1 "\drg"

c 'Теперь Боб может добавить столбец:'
s 1 '\c - bob'
PSQL_PROMPT1='bob=> '
s 1 'ALTER TABLE test ADD description text;'

c 'И даже удалить таблицу:'
s 1 'DROP TABLE test;'

stop_here

psql_close 1

