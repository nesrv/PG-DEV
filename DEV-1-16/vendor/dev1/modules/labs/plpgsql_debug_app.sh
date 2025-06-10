#!/bin/bash

. ../lib

init_app
roll_to 18

start_here

###############################################################################
h '1. Функция get_catalog'

c 'Текст динамического запроса формируем в отдельной переменной, которую перед выполнением запишем в журнал сервера. Для более полной информации включим в сообщение значения переданных в функцию параметров.'
c 'Отладочные строки в журнале можно найти по подстроке «DEBUG get_catalog».'
c 'После отладки команду RAISE LOG можно удалить или закомментировать.'

s 1 "CREATE OR REPLACE FUNCTION get_catalog(
    author_name text,
    book_title text,
    in_stock boolean
)
RETURNS TABLE(book_id integer, display_name text, onhand_qty integer)
AS \$\$
DECLARE
    title_cond text := '';
    author_cond text := '';
    qty_cond text := '';
    cmd text := '';
BEGIN
    IF book_title != '' THEN
        title_cond := format(
            ' AND cv.title ILIKE %L', '%'||book_title||'%'
        );
    END IF;
    IF author_name != '' THEN
        author_cond := format(
            ' AND cv.authors ILIKE %L', '%'||author_name||'%'
        );
    END IF;
    IF in_stock THEN
        qty_cond := ' AND cv.onhand_qty > 0';
    END IF;
    cmd := '
        SELECT cv.book_id, 
               cv.display_name,
               cv.onhand_qty
        FROM   catalog_v cv
        WHERE  true'
        || title_cond || author_cond || qty_cond || '
        ORDER BY display_name';

    RAISE LOG 'DEBUG get_catalog (%, %, %): %',
        author_name, book_title, in_stock, cmd;
    RETURN QUERY EXECUTE cmd;
END
\$\$ STABLE LANGUAGE plpgsql;"

###############################################################################
h '2. Включение и выключение трассировки SQL-запросов'

c 'Чтобы включить трассировку всех запросов на уровне сервера, можно выполнить:'

s 1 "ALTER SYSTEM SET log_min_duration_statement = 0;"
s 1 "SELECT pg_reload_conf();"

c 'Чтобы выключить:'

s 1 "ALTER SYSTEM RESET log_min_duration_statement;"
s 1 "SELECT pg_reload_conf();"

c 'Последние две команды попали в журнал сообщений:'

e "tail -n 6 $LOG"

###############################################################################

stop_here
cleanup_app
