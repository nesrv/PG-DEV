#!/bin/bash

. ../lib

init

psql_open A 2

start_here

###############################################################################
h '1. Внутристраничная очистка'

c 'Создадим таблицу с двумя полями.'
c 'Параметр fillfactor установим в 75%, как в демонстрации.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 'CREATE TABLE t(
  id integer GENERATED ALWAYS AS IDENTITY, 
  s char(2000)
)
WITH (fillfactor = 75);'

c 'Создадим индекс по столбцу s:'

s 1 'CREATE INDEX t_s ON t(s);'

c 'Как обычно, используем расширение pageinspect.'

s 1 'CREATE EXTENSION pageinspect;'

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

c 'Cоздадим представление для работы с индексом — такое же, как в демонстрации:'

s 1 "CREATE VIEW t_s_v AS
SELECT itemoffset,
       ctid
FROM bt_page_items('t_s',1);"

c 'Добавим строку и будем обновлять столбец s:'

s 1 "INSERT INTO t(s) VALUES ('A');"
s 1 "UPDATE t SET s = 'B';"
s 1 "UPDATE t SET s = 'C';"
s 1 "UPDATE t SET s = 'D';"

c 'Наличие индекса на обновляемом столбце привело к тому, что внутристраничное обновление не использовалось:'

s 1 "SELECT * FROM t_v;"

c 'Как и в демонстрации, еще одно обновление строки приводит к внутристраничной очистке:'

s 1 "UPDATE t SET s = 'E';"
s 1 "SELECT * FROM t_v;"

c 'Все неактуальные версии строк (0,1), (0,2) и (0,3) очищены; после этого на освободившееся место добавлена новая версия строки (0,5).'
c 'Указатели на очищенные строки не освобождены, а имеют статус dead.'

###############################################################################
h '2. HOT-обновление при наличии индекса'

c 'Удалим индекс по столбцу s и добавим другой, по столбцу id:'

s 1 'DROP INDEX t_s;'
s 1 'CREATE INDEX t_id ON t(id);'

s 1 "CREATE VIEW t_id_v AS
SELECT itemoffset,
       ctid
FROM bt_page_items('t_id',1);"

c 'Опустошим таблицу и повторим команды, приводящие к внутристраничной очистке:'

s 1 "TRUNCATE t;"
s 1 "INSERT INTO t(s) VALUES ('A');"
s 1 "UPDATE t SET s = 'B';"
s 1 "UPDATE t SET s = 'C';"
s 1 "UPDATE t SET s = 'D';"

c 'В индексной странице только одна ссылка на таблицу:'

s 1 "SELECT * FROM t_id_v;"

c 'В табличной странице — версии строки, объединенные в список:'

s 1 "SELECT * FROM t_v;"

c 'Индекс на столбце не мешает HOT-обновлению, если этот столбец не обновляется.'

###############################################################################
h '3. Разрыв HOT-цепочки'

s 2 "\c $TOPIC_DB"
s 2 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
s 2 "SELECT count(*) FROM t;"

c 'Теперь выполняем обновление в первом сеансе:'

s 1 "UPDATE t SET s = 'I';"
s 1 "UPDATE t SET s = 'J';"
s 1 "UPDATE t SET s = 'K';"

s 1 "SELECT * FROM t_v;"

c 'Следующее обновление уже не сможет освободить место на странице:'

s 1 "UPDATE t SET s = 'L';"
s 1 "SELECT * FROM t_v;"

c 'Видим ссылку (1,1), ведущую на страницу 1.'

c 'Представление pg_stat_all_tables покажет количество измененных строк (в том числе с применением HOT), а также количество измененных строк с переходом на новую табличную страницу.'\
' Если это значение при работе с таблицей будет достаточно большим, то следует задуматься об уменьшении значения fillfactor.'

# Чорная магия, чтобы статистика долетела до stats collector
sleep 1
s_bare 1 "SELECT 1;" >/dev/null
sleep 3

s 1 "SELECT relname, n_tup_upd, n_tup_hot_upd, n_tup_newpage_upd
FROM pg_stat_all_tables WHERE relname = 't';"

c 'Теперь в индексе — две строки, каждая указывает на начало своей HOT-цепочки:'

s 1 "SELECT * FROM t_id_v;"

s 2 "COMMIT;"

###############################################################################

stop_here
cleanup
