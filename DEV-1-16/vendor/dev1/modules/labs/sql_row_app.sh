#!/bin/bash

. ../lib

init_app
roll_to 10

start_here

###############################################################################
h '1. Функция onhand_qty'

s 1 "CREATE FUNCTION onhand_qty(book books) RETURNS integer
STABLE LANGUAGE sql
BEGIN ATOMIC
    SELECT coalesce(sum(o.qty_change),0)::integer
    FROM operations o
    WHERE o.book_id = book.book_id;
END;"


s 1 "CREATE OR REPLACE VIEW catalog_v AS
SELECT b.book_id,
       book_name(b.book_id, b.title) AS display_name,
       b.onhand_qty
FROM   books b
ORDER BY display_name;"

###############################################################################
h '2. Функция get_catalog'

c 'Расширяем catalog_v заголовком книги и полным списком авторов (приложение игнорирует неизвестные ему поля).'
c 'Функция, возвращающая полный список авторов:'

s 1 "CREATE FUNCTION authors(book books) RETURNS text
STABLE LANGUAGE sql
BEGIN ATOMIC
    SELECT string_agg(
               a.last_name ||
               ' ' ||
               a.first_name ||
               coalesce(' ' || nullif(a.middle_name,''), ''),
               ', ' 
               ORDER BY ash.seq_num
           )
    FROM   authors a
           JOIN authorship ash ON a.author_id = ash.author_id
    WHERE  ash.book_id = book.book_id;
END;"

c 'Используем эту функцию в представлении catalog_v. Такое представление уже существует; мы пересоздадим его — изменим порядок столбцов и запрос:'

s 1 "DROP VIEW catalog_v;"

s 1 "CREATE VIEW catalog_v AS
SELECT b.book_id,
       b.title,
       b.onhand_qty,
       book_name(b.book_id, b.title) AS display_name,
       b.authors
FROM   books b
ORDER BY display_name;"

c 'Функция get_catalog теперь использует расширенное представление:'

s 1 "CREATE FUNCTION get_catalog(
    author_name text, 
    book_title text, 
    in_stock boolean
)
RETURNS TABLE(book_id integer, display_name text, onhand_qty integer)
STABLE LANGUAGE sql
BEGIN ATOMIC
    SELECT cv.book_id, 
           cv.display_name,
           cv.onhand_qty
    FROM   catalog_v cv
    WHERE  cv.title   ILIKE '%'||coalesce(book_title,'')||'%'
    AND    cv.authors ILIKE '%'||coalesce(author_name,'')||'%'
    AND    (in_stock AND cv.onhand_qty > 0 OR in_stock IS NOT TRUE)
    ORDER BY display_name;
END;"

###############################################################################

stop_here
cleanup_app
