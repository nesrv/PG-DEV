#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Версии строк'

c 'Создаем расширение и таблицу.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE EXTENSION pageinspect;'
s 1 'CREATE TABLE t(s text);'

c 'Вставляем строку, обновляем ее и затем удаляем:'

s 1 "INSERT INTO t VALUES ('FOO');"
s 1 "UPDATE t SET s = 'BAR';"
s 1 "UPDATE t SET s = 'BAZ';"
s 1 "DELETE FROM t;"

c 'В таблице ничего нет:'

s 1 "SELECT * FROM t;"

c 'Проверяем версии в странице:'

s 1 "SELECT '(0,'||lp||')' AS ctid,
       t_xmin as xmin,
       t_xmax as xmax,
       CASE WHEN (t_infomask & 256) > 0  THEN 't' END AS xmin_c,
       CASE WHEN (t_infomask & 512) > 0  THEN 't' END AS xmin_a,
       CASE WHEN (t_infomask & 1024) > 0 THEN 't' END AS xmax_c,
       CASE WHEN (t_infomask & 2048) > 0 THEN 't' END AS xmax_a
FROM heap_page_items(get_raw_page('t',0))
ORDER BY lp;"

###############################################################################
h '2. Версии строк на определенной странице'

c 'Номер страницы содержится в первой компоненте значения ctid:'

s 1 "SELECT ctid FROM pg_class WHERE relname = 'pg_class';"

c 'К сожалению, тип данных tid не позволяет непосредственно получить номер страницы, но можно, например, воспользоваться приведением к типу point:'

s 1 "SELECT (ctid::text::point)[0]::integer FROM pg_class WHERE relname = 'pg_class';"

c 'Количество строк на той же странице:'

s 1 "SELECT count(*)
FROM pg_class
WHERE (ctid::text::point)[0]::integer = (
  SELECT (ctid::text::point)[0]::integer FROM pg_class WHERE relname = 'pg_class'
);"

###############################################################################
h '3. Режим ON_ERROR_ROLLBACK'

c 'Включим режим:'

s 1 "\set ON_ERROR_ROLLBACK on"

c 'Начнем транзакцию и вставим строку.'

s 1 "BEGIN;"
s 1 "INSERT INTO t VALUES ('FOO')
  RETURNING s, xmin, pg_current_xact_id();"

c 'Вставим еще одну строку.'

s 1 "INSERT INTO t VALUES ('BAR')
  RETURNING s, xmin, pg_current_xact_id();"

c 'Каждая команда происходит в отдельной вложенной транзакции, что и требовалось установить.'

s 1 "COMMIT;"

c 'Установленный режим будет действовать вплоть до завершения сеанса psql. А чтобы эта настройка не помешала дальнейшей работе в этом же сеансе, вернем прежний режим:'

s 1 "\set ON_ERROR_ROLLBACK off"

###############################################################################

stop_here
cleanup
