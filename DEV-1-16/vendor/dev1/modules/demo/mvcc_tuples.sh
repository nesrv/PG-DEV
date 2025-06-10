#!/bin/bash

. ../lib

init

start_here 5

###############################################################################
h 'Структура страниц'

c 'Для изучения структуры и содержания страниц предназначено расширение pageinspect.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE EXTENSION pageinspect;'

c 'Границы областей страницы записаны в ее заголовке. Возьмем для примера нулевую страницу одной из таблиц системного каталога:'

s 1 "SELECT lower, upper, special, pagesize
FROM page_header(get_raw_page('pg_class',0));"

c 'Области занимают следующие диапазоны адресов:'
ul '0 — начало заголовка страницы и указатели на версии строк,'
ul 'lower — начало свободного места,'
ul 'upper — начало данных (версий строк),'
ul 'special — начало спец. данных (только для индексов),'
ul 'pagesize — конец страницы.'

P 10

###############################################################################
h 'Вставка'

c 'Создадим таблицу и индекс:'

s 1 'CREATE TABLE t(
  n integer,
  s text
);'
s 1 'CREATE INDEX t_s on t(s);'

c 'Для удобства создадим представление, которое с помощью расширения pageinspect покажет интересующую нас информацию о версиях строк из нулевой страницы таблицы:'

s 1 "CREATE VIEW t_v AS
SELECT '(0,'||lp||')' AS ctid,
       CASE lp_flags
         WHEN 0 THEN 'unused'
         WHEN 1 THEN 'normal'
         WHEN 2 THEN 'redirect to '||lp_off
         WHEN 3 THEN 'dead'
       END AS state,
       t_xmin as xmin,
       t_xmax as xmax,
       CASE WHEN (t_infomask & 256) > 0  THEN 't' END AS xmin_c,
       CASE WHEN (t_infomask & 512) > 0  THEN 't' END AS xmin_a,
       CASE WHEN (t_infomask & 1024) > 0 THEN 't' END AS xmax_c,
       CASE WHEN (t_infomask & 2048) > 0 THEN 't' END AS xmax_a
FROM heap_page_items(get_raw_page('t',0))
ORDER BY lp;"

c 'Также создадим представление, чтобы заглянуть в индекс. Нулевая страница индекса содержит метаинформацию, поэтому смотрим в первую:'

s 1 "CREATE VIEW t_s_v AS
SELECT itemoffset,
       ctid
FROM bt_page_items('t_s',1);"

c 'Вставим одну строку, предварительно начав транзакцию.'

MAGIC_NUMBER=42

s 1 "BEGIN;"
s 1 "INSERT INTO t VALUES ($MAGIC_NUMBER, 'FOO');"

c 'Вот номер нашей текущей транзакции и ее статус:'

s 1 "SELECT pg_current_xact_id(); -- txid_current() до версии 13"
export XID=$(s_bare 1 "SELECT pg_current_xact_id();")

s 1 "SELECT pg_xact_status('$XID');"

c 'Вот что содержится в табличной странице:'

s 1 "SELECT * FROM t_v;"

c 'Похожую, но существенно менее детальную информацию можно получить и из самой таблицы, используя псевдостолбцы ctid, xmin и xmax:'

s 1 "SELECT ctid, xmin, xmax, * FROM t;"

c 'В индексной странице видим один указатель на единственную строку таблицы:'

s 1 "SELECT * FROM t_s_v;"

P 12

###############################################################################
h 'Фиксация изменений'

c 'Выполним фиксацию:'

s 1 "COMMIT;"

c 'Что изменилось в странице?'

s 1 "SELECT * FROM t_v;"

c 'Ничего, так как единственная операция, которая выполняется при фиксации — запись статуса транзакции в CLOG.'

s 1 "SELECT pg_xact_status('$XID');"

c 'Информация о статусах транзакций хранится в подкаталоге pg_xact каталога PGDATA и кешируется в общей памяти. Начиная с PostgreSQL 13, статистику использования кешей, в том числе кеша статусов транзакций, показывает представление pg_stat_slru:'

s 1 "SELECT name, blks_hit, blks_read, blks_written
FROM pg_stat_slru WHERE name = 'Xact';"

p

c 'Транзакция, первой обратившаяся к странице, должна будет определить статус транзакции xmin. Этот статус будет записан в информационные биты:'

s 1 "SELECT * FROM t;"
s 1 "SELECT * FROM t_v;"

P 14

###############################################################################
h 'Удаление'

c 'Теперь удалим строку.'

s 1 "BEGIN;"
s 1 "DELETE FROM t;"
export XID=$(s_bare 1 "SELECT pg_current_xact_id();")

c 'Номер транзакции записался в поле xmax:'

s 1 "SELECT * FROM t_v;"

P 16

###############################################################################
h 'Отмена изменений'

c 'При обрыве транзакции номер xmax остается в заголовке.'

s 1 "ROLLBACK;"
s 1 "SELECT pg_xact_status('$XID');"
s 1 "SELECT * from t_v;"

c 'А при первом обращении к странице выставляется соответствующий бит:'

s 1 "SELECT * FROM t;"
s 1 "SELECT * FROM t_v;"

P 18

###############################################################################
h 'Обновление'

c 'Теперь проверим обновление.'

s 1 "UPDATE t SET s = 'BAR';"

c 'Запрос выдает одну строку (новую версию):'

s 1 "SELECT * FROM t;"

c 'Но в странице мы видим обе версии. Причем новый номер транзакции записался на место старого (поскольку старая транзакция была отменена).'

s 1 "SELECT * FROM t_v;"

c 'При этом в индексной странице обнаруживаем указатели на обе версии:'

s 1 "SELECT * FROM t_s_v;"

c 'Индексные записи внутри страницы упорядочены по значению ключа. Поэтому первой идет запись с ключом BAR (ссылается на версию (0,2)), а второй — запись с ключом FOO (ссылается на версию (0,1)).'

P 21

###############################################################################
h 'Точки сохранения и вложенные транзакции'

c 'Опустошим таблицу (при этом опустошаются файлы таблицы и индекса):'

s 1 'TRUNCATE t;'

c 'Начинаем транзакцию и вставляем строку.'

s 1 "BEGIN;"

s 1 "INSERT INTO t(n) VALUES ($MAGIC_NUMBER)
  RETURNING *, ctid, xmin, xmax;"
export XID=$(s_bare 1 "SELECT pg_current_xact_id();")

c 'Ставим точку сохранения и удаляем строку.'

s 1 "SAVEPOINT sp;"

ss 1 "DELETE FROM t RETURNING *, ctid, xmin, xmax;"

export DEL_OUT=$(r 1)
echo "$DEL_OUT"

export XID1=$(echo "$DEL_OUT" | awk -F '|' "/$MAGIC_NUMBER/{gsub(/ /, \"\", \$NF); print \$NF}")

c 'Обратите внимание: функция pg_current_xact_id() выдает номер основной, а не вложенной, транзакции:'

s 1 "SELECT pg_current_xact_id();"

p

c 'Откатимся к точке сохранения. Версии строк в странице остаются на месте, но изменится статус вложенной транзакции:'

s 1 "ROLLBACK TO sp;"
s 1 "SELECT pg_xact_status('$XID') xid,
          pg_xact_status('$XID1') subxid;"

c 'Запрос к таблице снова покажет строку — ее удаление было отменено:'
s 1 "SELECT *, ctid, xmin, xmax FROM t;"

c "Для дальнейших изменений создается новая вложенная транзакция. Она заместит xmax в первой строке отмененной вложенной транзакции $XID1 и пропишется в xmin новой версии:"
s 1 "UPDATE t SET n = n + 1
  RETURNING *, ctid, xmin, xmax;"
export XID2=$(s_bare 1 "SELECT xmin FROM t WHERE n = $MAGIC_NUMBER + 1;")

s 1 "SELECT pg_xact_status('$XID') xid,
          pg_xact_status('$XID1') subxid1,
          pg_xact_status('$XID2') subxid2;"

c 'Фиксируем изменения. При этом в таблице, как и прежде, ничего не меняется:'

s 1 "COMMIT;"
s 1 "SELECT * FROM t_v;"

c 'А в CLOG основная транзакция и все вложенные, которые еще не завершены, получают статус committed:'

s 1 "SELECT pg_xact_status('$XID') xid,
          pg_xact_status('$XID1') subxid1,
          pg_xact_status('$XID2') subxid2;"

c 'Информация о вложенности транзакций хранится в подкаталоге pg_subtrans каталога PGDATA. Она кешируется в общей памяти, как и информация о статусах транзакций:'

s 1 "SELECT name, blks_hit, blks_read, blks_written
FROM pg_stat_slru WHERE name = 'Subtrans';"

###############################################################################

stop_here
cleanup
demo_end
