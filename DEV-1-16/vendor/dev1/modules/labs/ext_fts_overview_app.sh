#!/bin/bash

. ../lib

init 17

start_here

###############################################################################
h '1. Полнотекстовый поиск в приложении'

c 'Добавим столбец типа tsvector:'

s 1 "ALTER TABLE books ADD tsv tsvector;"

c 'Для поиска нам требуются данные нескольких таблиц, поэтому конструкция GENERATED ALWAYS не годится и придется воспользоваться триггером.'

c 'Начнем с функции, создающей необходимое значение tsvector:'

s 1 "CREATE FUNCTION build_tsv(
    book_id bigint, 
    title text, 
    abstract text
)
RETURNS tsvector
LANGUAGE sql STABLE
BEGIN ATOMIC
    WITH a(names) AS (
        SELECT string_agg(
            a.last_name || ' ' ||
            a.first_name || ' ' ||
            coalesce(a.middle_name,''),
            ' '
        )
        FROM authorships ash
            JOIN authors a ON a.author_id = ash.author_id
        WHERE ash.book_id = build_tsv.book_id
    )
    SELECT to_tsvector(
        'russian',
        build_tsv.title || ' ' ||
        a.names || ' ' ||
        coalesce(build_tsv.abstract,'')
    )
    FROM a;
END;"

c 'Мы используем конфигурацию поиска для русского языка, чтобы поиск работал без учета окончаний.'

c 'Теперь напишем триггерную функцию и триггер для таблицы books:'

s 1 "CREATE FUNCTION fill_tsv() RETURNS trigger
AS \$\$
BEGIN
    NEW.tsv := build_tsv(
        NEW.book_id, NEW.title, NEW.additional->>'Аннотация'
    );
    RETURN NEW;
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

s 1 "CREATE TRIGGER books_tsv
AFTER INSERT OR UPDATE OF title, additional
ON books
FOR EACH ROW
EXECUTE FUNCTION fill_tsv();"

c 'Но измениться может и имя автора, и состав авторов книги, поэтому также требуются триггеры на таблицы authors и authorships. Причем следует использовать триггеры AFTER, чтобы функция build_tsv брала из этих таблиц уже измененные данные.'

c 'В случае авторов надо найти все затронутые изменением книги и обновить у них tsv:'

s 1 "CREATE FUNCTION update_authors_tsv() RETURNS trigger
AS \$\$
BEGIN
    UPDATE books b
    SET tsv = build_tsv(b.book_id, b.title, b.additional->>'Аннотация')
    WHERE b.book_id IN (
        SELECT ash.book_id
        FROM authorships ash
            JOIN books b ON b.book_id = ash.book_id
        WHERE ash.author_id = NEW.author_id
    );
    RETURN NEW;
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

s 1 "CREATE TRIGGER authors_tsv
AFTER UPDATE OF first_name, last_name, middle_name
ON authors
FOR EACH ROW
EXECUTE FUNCTION update_authors_tsv();"

c 'Здесь мы предполагаем, что первичный ключ никогда не обновляется. Обратите внимание, что для таблицы books мы явно указали поля, на которые срабатывает триггер fill_tsv, так что триггер не будет срабатывать лишний раз.'

c 'И для авторства:'

s 1 "CREATE FUNCTION update_authorships_tsv() RETURNS trigger
AS \$\$
BEGIN
    UPDATE books b
    SET tsv = build_tsv(b.book_id, b.title, b.additional->>'Аннотация')
    WHERE b.book_id IN (OLD.book_id, NEW.book_id);
    RETURN NEW;
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

s 1 "CREATE TRIGGER authorships_tsv
AFTER INSERT OR UPDATE OF book_id, author_id OR DELETE
ON authorships
FOR EACH ROW
EXECUTE FUNCTION update_authorships_tsv();"

c 'Теперь обновим новый столбец у всех книг. Эту операцию, конечно, можно и нужно выполнять пакетно, как рассматривалось ранее, если количество строк велико.'

s 1 "UPDATE books
SET tsv = build_tsv(book_id, title, additional->>'Аннотация');"

c 'Наконец, заменим функцию search_cond, которая формирует условие поиска:'

s 1 "CREATE OR REPLACE FUNCTION public.search_cond(search text) RETURNS text
LANGUAGE sql IMMUTABLE
RETURN CASE
    WHEN coalesce(search,'') = '' THEN
        'true'
    ELSE
        format('b.tsv @@ websearch_to_tsquery(''russian'',%L)', search)
    END;"


###############################################################################

stop_here
cleanup_app
