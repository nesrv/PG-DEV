#!/bin/bash

. ../lib

init_app
roll_to 14

start_here

###############################################################################
h '1. Функция get_catalog'

# Внимание на защиту от внедрения SQL-кода

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
    cmd text;
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
    cmd := 'SELECT cv.book_id, 
               cv.display_name,
               cv.onhand_qty
        FROM   catalog_v cv
        WHERE  true'
        || title_cond || author_cond || qty_cond || '
        ORDER BY display_name';
    RAISE NOTICE '%', cmd;
    RETURN QUERY EXECUTE cmd;
END
\$\$ STABLE LANGUAGE plpgsql;"

###############################################################################

stop_here
cleanup_app
