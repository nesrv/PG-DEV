#!/bin/bash

. ../lib

init_app
roll_to 12

start_here

###############################################################################
h '1. Функция add_author'

s 1 "CREATE FUNCTION add_author(
    last_name text, 
    first_name text, 
    middle_name text
) RETURNS integer
AS \$\$
DECLARE
    author_id integer;
BEGIN
    INSERT INTO authors(last_name, first_name, middle_name)
        VALUES (last_name, first_name, middle_name)
        RETURNING authors.author_id INTO author_id;
    RETURN author_id;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

###############################################################################
h '2. Функция buy_book'

s 1 "CREATE FUNCTION buy_book(book_id integer)
RETURNS void
AS \$\$
BEGIN
    INSERT INTO operations(book_id, qty_change)
        VALUES (book_id, -1);
END
\$\$ VOLATILE LANGUAGE plpgsql;"

###############################################################################

stop_here
cleanup_app
