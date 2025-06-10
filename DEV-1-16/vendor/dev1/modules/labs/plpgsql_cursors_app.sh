#!/bin/bash

. ../lib

init_app
roll_to 13

start_here

###############################################################################
h '1. Функция book_name (сокращение авторов)'

c 'Напишем более универсальную функцию с дополнительным параметром — максимальное число авторов в названии.'
c 'Поскольку функция меняет сигнатуру (число и/или типы входных параметров), ее необходимо сначала удалить, а потом создать заново. В данном случае у функции есть зависимый объект — представление catalog_v, в котором она используется. Представление тоже придется пересоздать (в реальной работе все эти действия надо выполнять в одной транзакции, чтобы изменения вступили в силу атомарно).'

s 1 "DROP FUNCTION book_name(integer,text) CASCADE;"
s 1 "CREATE FUNCTION book_name(
    book_id integer, 
    title text, 
    maxauthors integer DEFAULT 2
)
RETURNS text
AS \$\$
DECLARE
    r record;
    res text := shorten(title);
BEGIN
    IF (right(res, 3) != '...') THEN res := res || '.'; END IF;
    res := res || ' ';
    FOR r IN (
        SELECT a.last_name, a.first_name, a.middle_name, ash.seq_num
        FROM   authors a
               JOIN authorship ash ON a.author_id = ash.author_id
        WHERE  ash.book_id = book_name.book_id
        ORDER BY ash.seq_num
    )
    LOOP
        EXIT WHEN r.seq_num > maxauthors;
        res := res || author_name(r.last_name, r.first_name, r.middle_name) || ', ';
    END LOOP;
    res := rtrim(res, ', ');
    IF r.seq_num > maxauthors THEN
        res := res || ' и др.';
    END IF;
    RETURN res;
END
\$\$ STABLE LANGUAGE plpgsql;"

s 1 "CREATE OR REPLACE VIEW catalog_v AS
SELECT b.book_id,
       b.title,
       b.onhand_qty,
       book_name(b.book_id, b.title) AS display_name,
       b.authors
FROM   books b
ORDER BY display_name;"

s 1 "SELECT book_id, display_name FROM catalog_v;"

c 'Не забудем также создать заново удаленную выше функцию get_catalog:'

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
h '2. Вариант на чистом SQL'

s 1 "CREATE OR REPLACE FUNCTION book_name(
    book_id integer, 
    title text, 
    maxauthors integer DEFAULT 2
)
RETURNS text 
STABLE LANGUAGE sql
BEGIN ATOMIC
SELECT shorten(book_name.title) ||
       CASE WHEN (right(shorten(book_name.title), 3) != '...') THEN '. '::text ELSE ' ' END ||
       string_agg(
           author_name(a.last_name, a.first_name, a.middle_name), ', '
           ORDER BY ash.seq_num
       ) FILTER (WHERE ash.seq_num <= maxauthors) ||
       CASE
           WHEN max(ash.seq_num) > maxauthors THEN ' и др.'
           ELSE ''
       END
FROM   authors a
       JOIN authorship ash ON a.author_id = ash.author_id
WHERE  ash.book_id = book_name.book_id;
END;"

s 1 "SELECT book_id, display_name FROM catalog_v;"

###############################################################################

stop_here
cleanup_app
