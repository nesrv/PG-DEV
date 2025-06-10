#!/bin/bash

. ../lib

init

start_here 7

###############################################################################
h 'HOT-обновление'

c 'Создадим таблицу. Для простоты не будем создавать индекс: любое обновление будет HOT-обновлением.'
c 'Каждая строка таблицы состоит из 2000 символов; если использовать только латинские буквы, то версия строки будет занимать 2000 байт плюс заголовок.'
c 'Параметр fillfactor установим в 75%, чтобы на страницу помещалось только три версии и одна была доступна для обновления.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE t(
  s char(2000)
)
WITH (fillfactor = 75);'

c 'Для изучения содержимого страницы используем расширение pageinspect.'

s 1 'CREATE EXTENSION pageinspect;'

c 'Для удобства создадим уже знакомое представление в немного более компактном виде и дополненное двумя полями:'

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

c 'Вставим строку и обновим ее, чтобы создать новую версию:'

s 1 "INSERT INTO t(s) VALUES ('A');"
s 1 "UPDATE t SET s = 'B';"

c 'Поскольку обновленный столбец не входит ни в какой индекс (в нашем случае ни одного индекса просто нет), в табличной странице появляется цепочка изменений:'

s 1 "SELECT * FROM t_v;"

ul 'флаг Heap Hot Updated показывает, что надо идти по цепочке ctid,'
ul 'флаг Heap Only Tuple показывает, что на данную версию строки нет ссылок из индексов.'

p

c 'При дальнейших изменениях цепочка будет расти (в пределах страницы):'

s 1 "UPDATE t SET s = 'C';"
s 1 "SELECT * FROM t_v;"

P 11

###############################################################################
h 'Внутристраничная HOT-очистка'

c 'Проверим, как работает внутристраничная очистка при HOT-обновлениях. Обновим строку еще раз:'

s 1 "UPDATE t SET s = 'D';"

c 'В странице сейчас четыре версии строки:'

s 1 "SELECT * FROM t_v;"


export UPPER=$(s_bare 1 "SELECT upper FROM page_header(get_raw_page('t',0));")
export PAGESIZE=$(s_bare 1 "SELECT pagesize FROM page_header(get_raw_page('t',0));")
export FILLED=$(s_bare 1 "SELECT pagesize-upper FROM page_header(get_raw_page('t',0));")

c "На самом деле мы только что превысили порог fillfactor. 75% от размера страницы составляет 6144 байтов, а разница между значениями pagesize и upper равна $PAGESIZE-$UPPER=$FILLED:" 

s 1 "SELECT lower, upper, pagesize FROM page_header(get_raw_page('t',0));"

c 'Проверим, что порог действительно превышен. Обновим строку еще раз:'

s 1 "UPDATE t SET s = 'E';"

c 'Какие изменения произойдут со страницей?'

s 1 "SELECT * FROM t_v;"

c 'Все неактуальные версии строк (0,1), (0,2) и (0,3) были очищены; после этого новая версия строки была добавлена на освободившееся место.'
c 'Указатели на очищенные строки освобождены (имеют статус unused).'
c 'При этом указатель на первую версию остался на месте, но получил статус redirect. Проследите ссылки от этой головной версии до конца HOT-цепочки.'

p

c 'Выполним обновление еще несколько раз:'

s 1 "UPDATE t SET s = 'F';"
s 1 "UPDATE t SET s = 'G';"
s 1 "SELECT * FROM t_v;"

c 'Следующее обновление снова вызывает очистку:'

s 1 "UPDATE t SET s = 'H';"
s 1 "SELECT * FROM t_v;"

c 'А теперь построим индекс по столбцу s и создадим вспомогательное представление, чтобы заглянуть в него:'

s 1 "CREATE INDEX t_s ON t(s);"

s 1 "CREATE VIEW t_s_v AS
SELECT itemoffset,
       ctid
FROM bt_page_items('t_s',1);"

c 'При создании индекса перестройки данных в табличных страницах не происходит, HOT-цепочки сохраняются:'

s 1 "SELECT * FROM t_v;"

c 'А из индекса ссылка ведет к указателю начала цепочки:'

s 1 "SELECT * FROM t_s_v;"

###############################################################################

stop_here
cleanup
demo_end
