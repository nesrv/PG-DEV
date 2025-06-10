#!/bin/bash

. ../lib

init

# Иначе статистика испортит вторую часть демо
s 1 "ALTER SYSTEM SET autovacuum = off;"
pgctl_reload A

psql_open A 2

start_here 9

###############################################################################
h 'Обычная очистка'

c 'Создадим таблицу и индекс.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE t(id integer);'
s 1 'CREATE INDEX t_id ON t(id);'

c 'Как обычно, используем расширение pageinspect:'

s 1 'CREATE EXTENSION pageinspect;'

c 'А также представление для табличной страницы:'

s 1 "CREATE VIEW t_v AS
SELECT '(0,'||lp||')' AS ctid,
       CASE lp_flags
         WHEN 0 THEN 'unused'
         WHEN 1 THEN 'normal'
         WHEN 2 THEN 'redirect to '||lp_off
         WHEN 3 THEN 'dead'
       END AS state,
       t_xmin || CASE
         WHEN (t_infomask & 256) > 0 THEN ' (c)'
         WHEN (t_infomask & 512) > 0 THEN ' (a)'
         ELSE ''
       END AS xmin,
       t_xmax || CASE
         WHEN (t_infomask & 1024) > 0 THEN ' (c)'
         WHEN (t_infomask & 2048) > 0 THEN ' (a)'
         ELSE ''
       END AS xmax,
       CASE WHEN (t_infomask2 & 16384) > 0 THEN 't' END AS hhu,
       CASE WHEN (t_infomask2 & 32768) > 0 THEN 't' END AS hot,
       t_ctid
FROM heap_page_items(get_raw_page('t',0))
ORDER BY lp;"

c 'И представление для индекса:'

s 1 "CREATE VIEW t_id_v AS
SELECT itemoffset,
       ctid
FROM bt_page_items('t_id',1);"

c 'Вставим строку в таблицу и обновим ее:'

s 1 "INSERT INTO t VALUES (1);"
s 1 "UPDATE t SET id = 2;"

c 'Теперь, чтобы еще раз напомнить про понятие горизонта, откроем в другом сеансе транзакцию с активным снимком данных.'

s 2 "\c $TOPIC_DB"
s 2 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
s 2 "SELECT * FROM t;"

c 'Горизонт базы данных определяется этим снимком:'

s 2 "SELECT backend_xmin FROM pg_stat_activity WHERE pid = pg_backend_pid();"

c 'Снова обновим строку.'

s 1 "UPDATE t SET id = 3;"

c 'Сейчас в таблице три версии строки:'

s 1 "SELECT * FROM t_v;"

c 'Выполним теперь очистку.'

s 1 "VACUUM t;"

c 'Как изменится табличная страница?'

s 1 "SELECT * FROM t_v;"

c 'Очистка освободила одну версию строки, а вторая осталась без изменений, так как параллельная транзакция до сих пор не завершена и ее снимок активен.'

c 'В индексе — два указателя на оставшиеся версии:'

s 1 "SELECT * FROM t_id_v;"

c 'Можно попросить очистку рассказать о том, что происходит:'

s 1 "VACUUM VERBOSE t;"

c 'Обратите внимание:'
ul 'tuples: 0 removed, 2 remain'
ul '1 are dead but not yet removable,'
ul 'index scan not needed'
ul 'removable cutoff показывает текущий горизонт'

p

c 'Теперь завершим параллельную транзакцию и снова вызовем очистку.'

s 2 "COMMIT;"

s 1 "VACUUM VERBOSE t;"

c 'Горизонт сдвинулся вперед и позволил очистке удалить мертвую строку — tuples: 1 removed. Теперь в странице осталась только последняя актуальная версия строки:'

s 1 "SELECT * FROM t_v;"

c 'В индексе также только одна запись:'

s 1 "SELECT * FROM t_id_v;"

###############################################################################
P 13
h 'Анализ'

c 'Создадим таблицу с большим количеством одинаковых строк и проиндексируем ее:'
s 1 "CREATE TABLE tt(s) AS SELECT 'FOO' FROM generate_series(1,1000000) AS g;"
s 1 "CREATE INDEX ON tt(s);"

c 'Планировщик ничего не знает про данные и выбирает индексный доступ, хотя читать придется всю таблицу:'
s 1 "EXPLAIN (costs off) SELECT * FROM tt WHERE s = 'FOO';"

c 'При анализе собирается статистика по случайной выборке строк:'
s 1 "ANALYZE VERBOSE tt;"

c 'Статистика сохраняется в системном каталоге. После этого планировщик знает, что во всех строках находится одно и то же значение, и перестанет использовать индекс:'
s 1 "EXPLAIN (costs off) SELECT * FROM tt WHERE s = 'FOO';"

###############################################################################
P 17
h 'Полная очистка'

c 'Файлы, занимаемые таблицей и индексом:'

s 1 "SELECT pg_relation_filepath('t'), pg_relation_filepath('t_id');"

c 'Вызываем полную очистку.'

s 1 "VACUUM FULL VERBOSE t;"

c 'Таблица и индекс теперь полностью перестроены:'

s 1 "SELECT * FROM t_v;"
s 1 "SELECT * FROM t_id_v;"

c 'Имена файлов поменялись:'

s 1 "SELECT pg_relation_filepath('t'), pg_relation_filepath('t_id');"

###############################################################################

stop_here
cleanup
demo_end
