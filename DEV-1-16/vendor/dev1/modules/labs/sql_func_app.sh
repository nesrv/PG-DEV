#!/bin/bash

. ../lib

init_app
roll_to 8

start_here

###############################################################################
h '1. Функция author_name'

s 1 "CREATE FUNCTION author_name(
    last_name text,
    first_name text,
    middle_name text
) RETURNS text
LANGUAGE sql IMMUTABLE 
RETURN last_name || ' ' ||
       left(first_name, 1) || '.' ||
       CASE WHEN middle_name != '' -- подразумевает NOT NULL
           THEN ' ' || left(middle_name, 1) || '.'
           ELSE ''
       END;"


c 'Категория изменчивости — immutable. Функция всегда возвращает одинаковое значение при одних и тех же входных параметрах.'

s 1 "CREATE OR REPLACE VIEW authors_v AS
SELECT a.author_id,
       author_name(a.last_name, a.first_name, a.middle_name) AS display_name
FROM   authors a
ORDER BY display_name;"

###############################################################################
h '2. Функция book_name'

s 1 "CREATE FUNCTION book_name(book_id integer, title text)
RETURNS text
LANGUAGE sql STABLE 
RETURN (
SELECT title || '. ' ||
       string_agg(
           author_name(a.last_name, a.first_name, a.middle_name), ', '
           ORDER BY ash.seq_num
       )
FROM   authors a
       JOIN authorship ash ON a.author_id = ash.author_id
WHERE  ash.book_id = book_name.book_id
);"

c 'Категория изменчивости — stable. Функция возвращает одинаковое значение при одних и тех же входных параметрах, но только в рамках одного SQL-запроса.'


s 1 "CREATE OR REPLACE VIEW catalog_v AS
SELECT b.book_id,
       book_name(b.book_id, b.title) AS display_name
FROM   books b
ORDER BY display_name;"

###############################################################################

stop_here
cleanup_app
