#!/bin/bash

. ../lib

init

start_here 13

###############################################################################
h 'Заморозка'

c 'Установим для демонстрации параметры заморозки.'

c 'Небольшой возраст транзакции:'
s 1 "ALTER SYSTEM SET vacuum_freeze_min_age = 1;"

c 'Возраст, после которого будет выполняться заморозка всех страниц:'
s 1 "ALTER SYSTEM SET vacuum_freeze_table_age = 3;"

c 'И отключим автоматическую очистку, чтобы запускать ее вручную в нужный момент.'

s 1 "ALTER SYSTEM SET autovacuum = off;"

s 1 "SELECT pg_reload_conf();"

c 'Создадим таблицу с данными. Установим минимальный fillfactor: на каждой странице будет всего две строки.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE TABLE t(id integer, s char(300)) WITH (fillfactor = 10);"

c 'Создадим представление для наблюдения за битами-подсказками на первых двух страницах таблицы.'
c 'Сейчас нас интересует только xmin и биты, которые относятся к нему, поскольку версии строк с ненулевым xmax будут очищены. Кроме того, выведем и возраст транзакции xmin.'

s 1 'CREATE EXTENSION pageinspect;'
s 1 "CREATE VIEW t_v AS
SELECT '('||blkno||','||lp||')' as ctid,
       CASE lp_flags
         WHEN 0 THEN 'unused'
         WHEN 1 THEN 'normal'
         WHEN 2 THEN 'redirect to '||lp_off
         WHEN 3 THEN 'dead'
       END AS state,
       t_xmin AS xmin,
       age(t_xmin) AS xmin_age,
       CASE WHEN (t_infomask & 256) > 0 THEN 't' END AS xmin_c,
       CASE WHEN (t_infomask & 512) > 0 THEN 't' END AS xmin_a,
       t_xmax AS xmax
FROM (
  SELECT 0 blkno, * FROM heap_page_items(get_raw_page('t',0))
  UNION ALL
  SELECT 1 blkno, * FROM heap_page_items(get_raw_page('t',1))
) q
ORDER BY blkno, lp;"

c 'Для того чтобы заглянуть в карту видимости и заморозки, воспользуемся еще одним расширением:'

s 1 "CREATE EXTENSION pg_visibility;"

c 'Вставляем данные. Сразу выполним очистку, чтобы заполнить карту видимости.'

s 1 "INSERT INTO t(id, s) SELECT g.id, 'FOO' FROM generate_series(1,100) g(id);"
s 1 "VACUUM t;"

c 'После очистки обе страницы отмечены в карте видимости (all_visible):'

s 1 "SELECT * FROM generate_series(0,1) g(blkno), pg_visibility_map('t',g.blkno)
ORDER BY g.blkno;"

c 'Каков возраст транзакции, создавшей строки?'

s 1 "SELECT * FROM t_v;"

c 'Возраст равен 1; версии строк с такой транзакцией еще не будут заморожены.'

p

c 'Обновим строку на нулевой странице. Новая версия попадет на ту же страницу благодаря небольшому значению fillfactor.'

s 1 "UPDATE t SET s = 'BAR' WHERE id = 1;"
s 1 "SELECT * FROM t_v;"

c 'Сейчас нулевая страница уже будет обработана заморозкой:'
ul 'возраст транзакции превышает значение, установленное в vacuum_freeze_min_age;'
ul 'страница изменена и исключена из карты видимости.'

s 1 "SELECT * FROM generate_series(0,1) g(blkno), pg_visibility_map('t',g.blkno)
ORDER BY g.blkno;"

c 'Выполняем очистку.'

s 1 "VACUUM t;"

c 'Очистка обработала измененную страницу. У одной версии строки установлены оба бита — это признак заморозки. Другая версия строки слишком молода, однако тоже была заморожена при проходе страницы (это позволило отметить нулевую страницу в карте заморозки):'

s 1 "SELECT * FROM t_v;"

c 'Теперь обе страницы отмечены в карте видимости (все версии строк на них актуальны). Очистка теперь не будет обрабатывать ни одну из этих страниц, и незамороженные версии строк на первой странице так и останутся незамороженными.'

s 1 "SELECT * FROM generate_series(0,1) g(blkno), pg_visibility_map('t',g.blkno)
ORDER BY g.blkno;"

c 'Именно для такого случая и требуется параметр vacuum_freeze_table_age, определяющий, в какой момент нужно просмотреть страницы, отмеченные в карте видимости, если они не отмечены в карте заморозки.'

c 'Для каждой таблицы сохраняется наибольший номер транзакции, для которого все версии строк с меньшими номерами xmin гарантированно заморожены. Ее возраст и сравнивается со значением параметра.'

s 1 "SELECT relfrozenxid, age(relfrozenxid) FROM pg_class WHERE relname = 't';"

c 'Сымитируем выполнение еще одной транзакции, чтобы возраст relfrozenxid таблицы достиг значения параметра vacuum_freeze_table_age.'

s 1 "SELECT pg_current_xact_id();"

s 1 "SELECT relfrozenxid, age(relfrozenxid) FROM pg_class WHERE relname = 't';"
s 1 "VACUUM t;"

c 'Теперь, поскольку гарантированно была проверена вся таблица, номер замороженной транзакции можно увеличить — мы уверены, что в страницах не осталось более старой незамороженной транзакции.'

s 1 "SELECT relfrozenxid, age(relfrozenxid) FROM pg_class WHERE relname = 't';"

c 'Вот что получилось в страницах:'

s 1 "SELECT * FROM t_v;"

c 'Обе страницы теперь отмечены в карте заморозки.'

s 1 "SELECT * FROM generate_series(0,1) g(blkno), pg_visibility_map('t',g.blkno)
ORDER BY g.blkno;"

c 'Номер последней замороженной транзакции есть и на уровне всей БД:'

s 1 "SELECT datname, datfrozenxid, age(datfrozenxid)
FROM pg_database;"

c 'Он устанавливается в минимальное значение из relfrozenxid всех таблиц этой БД. Если возраст datfrozenxid превысит значение параметра autovacuum_freeze_max_age, автоочистка будет запущена принудительно.'

###############################################################################

stop_here
cleanup
demo_end
