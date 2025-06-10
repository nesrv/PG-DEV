#!/bin/bash

. ../lib

init_app
roll_to 16

start_here

###############################################################################
h '1. Обработка повторяющихся авторов при добавлении книги'

s 1 "CREATE OR REPLACE FUNCTION add_book(title text, authors integer[])
RETURNS integer
AS \$\$
DECLARE
    book_id integer;
    id integer;
    seq_num integer := 1;
BEGIN
    INSERT INTO books(title)
        VALUES(title)
        RETURNING books.book_id INTO book_id;
    FOREACH id IN ARRAY authors LOOP
        INSERT INTO authorship(book_id, author_id, seq_num)
            VALUES (book_id, id, seq_num);
        seq_num := seq_num + 1;
    END LOOP;
    RETURN book_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Один и тот же автор не может быть указан дважды';
END
\$\$ VOLATILE LANGUAGE plpgsql;"

###############################################################################

stop_here
cleanup_app
