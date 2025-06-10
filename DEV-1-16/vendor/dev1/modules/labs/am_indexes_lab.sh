#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Сравнение размера и времени создания индексов'

c 'Посмотрим структуру таблицы tickets:'

s 1 "\d tickets"

c 'Поле book_ref имеет фиксированный размер, а поле contact_data имеет тип jsonb.'

c 'Включим подсчет времени выполнения запросов:'

s 1 "\timing on"

c 'Создадим hash-индексы...'

s 1 "CREATE INDEX tickets_hash_br ON tickets USING hash(book_ref);"
s 1 "CREATE INDEX tickets_hash_cd ON tickets USING hash(contact_data);"

c '...и индексы B-tree:'

s 1 "CREATE INDEX tickets_btree_br ON tickets(book_ref);"
s 1 "CREATE INDEX tickets_btree_cd ON tickets(contact_data);"

c 'Время создания хеш-индексов примерно одинаково, а время создания btree-индексов зависит от размера индексируемого поля.'

s 1 "\timing off"

c 'Теперь проверим размеры полученных индексов:'

s 1 "SELECT pg_size_pretty(pg_total_relation_size('tickets_hash_br')) \"hash book_ref\",
  pg_size_pretty(pg_total_relation_size('tickets_hash_cd')) \"hash contact_data\",
  pg_size_pretty(pg_total_relation_size('tickets_btree_br')) \"btree book_ref\",
  pg_size_pretty(pg_total_relation_size('tickets_btree_cd')) \"btree contact_data\" \gx"

c 'Размер hash-индексов тоже примерно одинаковый. А размер индексов B-tree (как и время их построения) зависит от размера индексируемого поля, поскольку такие индексы хранят индексируемые значения.'

###############################################################################
h '2. Расширение pg_trgm'

c 'Выполним запрос:'

#PREWARM=`s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
#SELECT * FROM tickets
#WHERE contact_data->>'phone' LIKE '%1234%';"`

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT * FROM tickets
WHERE contact_data->>'phone' LIKE '%1234%';"

c 'Обратите внимание на количество прочитанных страниц (Buffers) — их почти пятьдесят тысяч.'

c 'Добавим расширение pg_trgm:'

s 1 "CREATE EXTENSION pg_trgm;"

c 'Создадим GIN-индекс с классом операторов gin_trgm_ops:'

s 1 "CREATE INDEX tickets_gin
  ON tickets USING GIN ((contact_data->>'phone') gin_trgm_ops);"
  
c 'Такой класс операторов ускоряет поиск по шаблону, который начинается на знак процента, и даже по регулярным выражениям. Индекс на основе B-дерева этого не позволяет.'
  
c 'Повторим запрос:'  

#PREWARM=`s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
#SELECT * FROM tickets
#WHERE contact_data->>'phone' LIKE '%1234%';"`

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT * FROM tickets
WHERE contact_data->>'phone' LIKE '%1234%';"

c 'Количество прочитанных страниц сократилось более чем на порядок, время выполнения существенно уменьшилось.'

stop_here
cleanup
demo_end
