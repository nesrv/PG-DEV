#!/bin/bash

. ../lib

init_app
roll_to 11

start_here

###############################################################################
h '1. Укорачивание названия книги'

c 'Напишем более универсальную функцию, принимающую строку, максимальную длину и суффикс, добавляемый при укорачивании. Это не потребует усложнения кода, и позволит обойтись без «магических констант».'

s 1 "CREATE FUNCTION shorten(
    s text,
    max_len integer DEFAULT 45,
    suffix text DEFAULT '...'
)
RETURNS text AS \$\$
DECLARE
    suffix_len integer := length(suffix);
BEGIN
    RETURN CASE WHEN length(s) > max_len
        THEN left(s, max_len - suffix_len) || suffix
        ELSE s
    END;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

c 'Проверим:'

s 1 "SELECT shorten(
    'Путешествия в некоторые удаленные страны мира в четырех частях: сочинение Лемюэля Гулливера, сначала хирурга, а затем капитана нескольких кораблей'
);"
s 1 "SELECT shorten(
    'Путешествия в некоторые удаленные страны мира в четырех частях: сочинение Лемюэля Гулливера, сначала хирурга, а затем капитана нескольких кораблей',
    30
);"

c 'Используем написанную функцию:'

s 1 "CREATE OR REPLACE FUNCTION book_name(book_id integer, title text)
RETURNS text
STABLE LANGUAGE sql
BEGIN ATOMIC
SELECT shorten(book_name.title) || 
       CASE WHEN (right(shorten(book_name.title), 3) != '...') THEN '. '::text ELSE ' ' END ||
       string_agg(
           author_name(a.last_name, a.first_name, a.middle_name), ', '
           ORDER BY ash.seq_num
       )
FROM   authors a
       JOIN authorship ash ON a.author_id = ash.author_id
WHERE  ash.book_id = book_name.book_id;
END;"

###############################################################################
h '2. Укорачивание названия книги с переносом по словам'

s 1 "CREATE OR REPLACE FUNCTION shorten(
    s text,
    max_len integer DEFAULT 45,
    suffix text DEFAULT '...'
)
RETURNS text
AS \$\$
DECLARE
    suffix_len integer := length(suffix);
    short text := suffix;
BEGIN
    IF length(s) < max_len THEN
        RETURN s;
    END IF;
    FOR pos in 1 .. least(max_len-suffix_len+1, length(s))
    LOOP
        IF substr(s,pos-1,1) != ' ' AND substr(s,pos,1) = ' ' THEN
            short := left(s, pos-1) || suffix;
        END IF;
    END LOOP;
    RETURN short;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

c 'Проверим:'

s 1 "SELECT shorten(
    'Путешествия в некоторые удаленные страны мира в четырех частях: сочинение Лемюэля Гулливера, сначала хирурга, а затем капитана нескольких кораблей'
);"
s 1 "SELECT shorten(
    'Путешествия в некоторые удаленные страны мира в четырех частях: сочинение Лемюэля Гулливера, сначала хирурга, а затем капитана нескольких кораблей',
    30
);"

###############################################################################

stop_here
cleanup_app
