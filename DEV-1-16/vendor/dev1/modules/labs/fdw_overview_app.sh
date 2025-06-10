#!/bin/bash

. ../lib

init 20

start_here
###############################################################################
h '1. Загрузка новых поступлений'

s 1 "CREATE EXTENSION file_fdw;"

s 1 "CREATE SERVER file_server
    FOREIGN DATA WRAPPER file_fdw;"
s 1 "CREATE FOREIGN TABLE new_books (
    last_name text,
    first_name text,
    middle_name text,
    title text,
    format text,
    pages integer,
    isbn text,
    abstract text,
    publisher text,
    year text,
    typeface text,
    edition integer,
    series text,
    cover_filename text
)
SERVER file_server
OPTIONS (
    filename '/home/$OSUSER/new_books.csv',
    format 'csv'
);"

c 'Здесь предполагается, что несколько процедур загрузки книг не будут запускаться параллельно. Если такой гарантии нет, в коде надо отдельно предусмотреть эту возможность, устанавливая необходимые блокировки.'

c 'Для сопоставления авторов используется нечеткий поиск с помощью триграмм. Оператор % отсекает совсем непохожих (предел похожести по умолчанию 0.3 слишком низок для нашего случая, поэтому увеличиваем его). Из оставшихся выбираем лучшее совпадение, упорядочивая кандидатов с помощью функции similarity.'

s 1 "CREATE EXTENSION pg_trgm;"
s 1 "SELECT set_limit(0.7); -- предел похожести для оператора %"

s 1 "DO \$\$
DECLARE
    i new_books;
    book_id bigint;
    author_id bigint;
    author_cause text;
    seq_num integer;
BEGIN
    FOR i IN SELECT * FROM new_books
    LOOP
        IF i.title IS NOT NULL THEN
            INSERT INTO books AS b(
                title, format, pages, additional, cover
            ) VALUES (
                i.title,
                i.format::text::book_format,
                i.pages,
                jsonb_build_object(
                    'ISBN',         i.isbn,
                    'Аннотация',    i.abstract,
                    'Издательство', i.publisher,
                    'Год выпуска',  i.year,
                    'Гарнитура',    i.typeface,
                    'Издание',      i.edition,
                    'Серия',        i.series
                ),
                pg_read_binary_file(
                    '/home/$OSUSER/covers/'||i.cover_filename
                )
            )
            RETURNING b.book_id INTO book_id;
            seq_num := 1;
            RAISE NOTICE 'Книга: % (%)', i.title, book_id;
        END IF;

        -- есть ли точное совпадение с имеющимся автором?
        SELECT a.author_id, 'точное совпадение'
        INTO author_id, author_cause
        FROM authors a
        WHERE a.last_name   = i.last_name
          AND a.first_name  = i.first_name
          AND a.middle_name = i.middle_name;
        -- если нет, то может найдется очень похожий?
        IF author_id IS NULL THEN
            SELECT a.author_id, 'НЕточное совпадение'
            INTO author_id, author_cause
            FROM authors a
            WHERE (a.last_name || a.first_name || a.middle_name) %
                  (i.last_name || i.first_name || i.middle_name)
            ORDER BY similarity(
                  (a.last_name || a.first_name || a.middle_name),
                  (i.last_name || i.first_name || i.middle_name)
            ) DESC
            LIMIT 1;
        END IF;
        -- если и похожего нет, то считаем автора новым
        IF author_id IS NULL THEN
            INSERT INTO authors AS a(first_name,last_name,middle_name)
                VALUES (i.first_name, i.last_name, i.middle_name)
                RETURNING a.author_id, 'новый'
		INTO author_id, author_cause;
        END IF;
        RAISE NOTICE '  Автор: %, % (%)',
            i.last_name, author_cause, author_id;

        INSERT INTO authorships(book_id, author_id, seq_num)
            VALUES (book_id, author_id, seq_num);
        seq_num := seq_num + 1;
    END LOOP;
END;
\$\$;"

s 1 "DROP FOREIGN TABLE new_books;"

###############################################################################

stop_here
cleanup_app
