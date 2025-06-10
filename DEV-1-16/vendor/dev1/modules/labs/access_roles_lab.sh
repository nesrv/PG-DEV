#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Создание ролей'

PSQL_PROMPT1='student=# '
s 1 'CREATE ROLE creator WITH CREATEDB CREATEROLE;'
s 1 'CREATE ROLE weak WITH LOGIN;'

###############################################################################
h '2. Проверка возможности создания БД'

s 1 '\c - weak'
PSQL_PROMPT1='weak=> '
s 1 'CREATE DATABASE access_roles;'
# ERROR:  permission denied to create database'

###############################################################################
h '3. Включение в группу'

s 1 '\c - student'
PSQL_PROMPT1='student=# '
s 1 'GRANT creator TO weak;'
s 1 '\drg'

s 1 '\c - weak'
PSQL_PROMPT1='weak=> '
s 1 'SET ROLE creator;'
s 1 'CREATE DATABASE access_roles;'
s 1 '\x \l a* \x'

stop_here

psql_close 1

