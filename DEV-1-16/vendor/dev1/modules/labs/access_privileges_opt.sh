#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Роль, таблица и привилегии'

s 1 'CREATE ROLE alice LOGIN;'
s 1 'CREATE ROLE bob LOGIN;'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB;"

c 'Разрешим Алисе и Бобу создавать объекты в схеме public.'
s 1 'GRANT CREATE ON SCHEMA public TO alice,bob;'

###############################################################################
h '2. Объекты Алисы'

s 1 '\c - alice'
PSQL_PROMPT1='alice=> '

s 1 'CREATE TABLE t (
id int GENERATED ALWAYS AS IDENTITY,
txt text );'
c 'Кроме таблицы создана последовательность.'
s 1 '\d'

vSEQ=$(s_bare 1 "SELECT pg_get_serial_sequence('t', 'id');")

c 'Алиса выдает права на последовательность Бобу, достаточные для получения последнего сгенерированного номера и генерации следующего.'
s 1 "GRANT USAGE ON SEQUENCE ${vSEQ} TO bob;"
s 1 '\dp'

s 1 "INSERT INTO t(txt) VALUES('Эх, раз...');"

###############################################################################
h '3. Объекты Боба'

psql_open A 2 -d $TOPIC_DB -U bob
PSQL_PROMPT2='bob=> '

s 2 "CREATE TABLE tab (
n int DEFAULT nextval('${vSEQ}'),
msg text );"

s 2 "INSERT INTO tab ( msg ) VALUES ('От Боба');"
s 2 'SELECT * FROM tab;'
c 'В строку таблицы tab Боба попало следующее значение из последовательности Алисы. Таблицу t Боб читать не может.'
s 2 'SELECT * FROM t;'

###############################################################################
h '4. В сеансе Алисы'

c 'Генерируемые последовательностью значения уникальны.'
s 1 "INSERT INTO t(txt) VALUES('Да еще раз...');"

c 'Следующее значение в поле id.'
s 1 'SELECT * FROM t;'

stop_here

psql_close 1
