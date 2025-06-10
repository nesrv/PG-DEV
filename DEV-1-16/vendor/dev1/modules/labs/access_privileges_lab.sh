#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Роли и база данных'

s 1 'CREATE ROLE alice LOGIN;'
s 1 'CREATE ROLE bob LOGIN;'

s 1 "CREATE DATABASE $TOPIC_DB OWNER alice;"
s 1 "\l $TOPIC_DB"

s 1 "\c $TOPIC_DB alice"
PSQL_PROMPT1='alice=> '

###############################################################################
h '2. Схема'

s 1 'CREATE SCHEMA alice;'
s 1 "CREATE TABLE t AS SELECT 1 \"id\", 'Таблица Алисы' \"txt\";"

c 'Права для Боба на схему.'
s 1 'GRANT CREATE,USAGE ON SCHEMA alice TO bob;'
s 1 '\dn+ alice'

c 'Права для Боба на таблицу.'
s 1 'GRANT SELECT ON t TO bob;'
s 1 '\dp t'

###############################################################################
h '3. Представление'

c 'Боб создает представление в схеме alice.'
s 1 '\c - bob'
PSQL_PROMPT1='bob=> '

s 1 'CREATE VIEW alice.v AS SELECT * FROM alice.t;'
s 1 'SELECT * FROM alice.v;'

###############################################################################
h '4. Доступ к представлению в сеансе Алисы'

s 1 '\c - alice'
PSQL_PROMPT1='alice=> '

s 1 'SELECT * FROM v;'

c 'Прав у Алисы на представление нет.'
s 1 '\dv v'
s 1 '\dp v'

stop_here

psql_close 1
