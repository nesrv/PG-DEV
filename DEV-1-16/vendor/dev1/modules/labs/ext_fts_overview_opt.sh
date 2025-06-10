#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Подготовка'

s 1 "CREATE DATABASE $TOPIC_DB;"
e "zcat ~/mail_messages.sql.gz | psql -d $TOPIC_DB"
s 1 "\c $TOPIC_DB"

s 1 "ALTER TABLE mail_messages
ADD search_vector tsvector GENERATED ALWAYS AS (
    to_tsvector('english',subject) || to_tsvector('english',body_plain)
) STORED;"

s 1 "ANALYZE mail_messages;"

###############################################################################
h '2. Поиск двух фраз'

c 'Запрос без индексов:'

s 1 '\timing on'
s 1 "SELECT count(*) FROM mail_messages
WHERE search_vector @@ to_tsquery('(vacuum <-> full) & (index <-> page)');"
s 1 '\timing off'

c 'Запрос с индексом GiST:'

s 1 "CREATE INDEX mm_gist ON mail_messages USING gist(search_vector);"
s 1 "SELECT pg_size_pretty(pg_indexes_size('mail_messages'));"

s 1 '\timing on'
s 1 "SELECT count(*) FROM mail_messages
WHERE search_vector @@ to_tsquery('(vacuum <-> full) & (index <-> page)');"
s 1 '\timing off'

s 1 "DROP INDEX mm_gist;"

p

c 'Запрос с индексом GIN:'

s 1 "CREATE INDEX mm_gin ON mail_messages USING gin(search_vector);"
s 1 "SELECT pg_size_pretty(pg_indexes_size('mail_messages'));"

s 1 '\timing on'
s 1 "SELECT count(*) FROM mail_messages
WHERE search_vector @@ to_tsquery('(vacuum <-> full) & (index <-> page)');"
s 1 '\timing off'

s 1 "DROP INDEX mm_gin;"

p

c 'Запрос с индексом RUM:'

s 1 "CREATE EXTENSION rum;"
s 1 "CREATE INDEX mm_rum ON mail_messages USING rum(search_vector);"
s 1 "SELECT pg_size_pretty(pg_indexes_size('mail_messages'));"

s 1 '\timing on'
s 1 "SELECT count(*) FROM mail_messages
WHERE search_vector @@ to_tsquery('(vacuum <-> full) & (index <-> page)');"
s 1 '\timing off'

s 1 "DROP INDEX mm_rum;"

c 'Следует учитывать, что скорость выполнения запросов зависит от многих причин (от состояния буферного кеша, от нагрузки на сервер и т. д.), поэтому запросы лучше выполнить по нескольку раз и усреднить результаты.'

###############################################################################
h '3. Поиск точной формы слова'

c 'Изменяем конфигурацию поиска.'

s 1 'ALTER TEXT SEARCH CONFIGURATION english
ALTER MAPPING FOR asciiword WITH simple;'

c 'Теперь преобразование сохраняет форму слова:'

s 1 "SELECT to_tsquery('vacuuming');"

c 'Пересоздаем столбец.'

s 1 "ALTER TABLE mail_messages
DROP search_vector;"
s 1 "ALTER TABLE mail_messages
ADD search_vector tsvector GENERATED ALWAYS AS (
    to_tsvector('english',subject) || to_tsvector('english',body_plain)
) STORED;"

s 1 "SELECT count(*) FROM mail_messages
WHERE search_vector @@ to_tsquery('vacuuming');"

###############################################################################

stop_here
cleanup
