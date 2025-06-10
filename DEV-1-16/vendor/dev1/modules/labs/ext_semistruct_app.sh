#!/bin/bash

. ../lib

init 11

start_here

###############################################################################
h '1. Дополнительные сведения о книгах'

c 'Приложение рассчитывает получить дополнительные сведения о книгах в столбце additional таблицы, возвращаемой вызовом webapi.get_catalog, которая, в свою очередь, обращается за данными к public.get_catalog. Последняя получает дополнительные атрибуты через отдельную функцию, которая сейчас возвращает пустой документ:'

s 1 '\sf get_additional' pgsql

c 'Изменим функцию следующим образом:'

s 1 "CREATE OR REPLACE FUNCTION public.get_additional(book books) RETURNS jsonb
LANGUAGE sql STABLE
RETURN jsonb_build_object(
        'ISBN',         book.isbn,
        'Аннотация',    book.abstract,
        'Издательство', book.publisher,
        'Год выпуска',  book.year,
        'Гарнитура',    book.typeface,
        'Издание',      book.edition,
        'Серия',        book.series
    );"


###############################################################################
h '2. Замена нескольких столбцов на один формата JSON'

c 'Добавим к таблице books необходимый столбец:'

s 1 "ALTER TABLE books ADD additional jsonb;"

c 'Если данные о книгах могут изменяться в процессе наших действий, мы можем создать триггер, который будет переносить изменения в новый столбец:'

s 1 "CREATE FUNCTION fill_additional() RETURNS trigger
AS \$\$
BEGIN
    NEW.additional := jsonb_build_object(
        'ISBN',         NEW.isbn,
        'Аннотация',    NEW.abstract,
        'Издательство', NEW.publisher,
        'Год выпуска',  NEW.year,
        'Гарнитура',    NEW.typeface,
        'Издание',      NEW.edition,
        'Серия',        NEW.series
    );
    RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE TRIGGER books_additional
BEFORE INSERT OR UPDATE OF
    isbn, abstract, publisher, year, typeface, edition, series
ON books
FOR EACH ROW
EXECUTE FUNCTION fill_additional();"

c 'Теперь перенесем в новый столбец исторические данные:'

s 1 "UPDATE books
SET additional = get_additional(books)
WHERE additional IS NULL;"

c 'Начиная с этого момента старые столбцы менять нельзя. Если бы у нас была процедура загрузки новых поступлений, ее следовало бы переделать на заполнение нового столбца.'
c 'Переключим приложение на использование нового столбца:'

s 1 "CREATE OR REPLACE FUNCTION public.get_additional(book books) RETURNS jsonb
LANGUAGE sql STABLE
RETURN book.additional;"

c 'Теперь можно удалить временный триггер:'

s 1 "DROP TRIGGER books_additional ON books;"
s 1 "DROP FUNCTION fill_additional;"

c 'И можно удалить ненужные теперь столбцы таблицы:'

s 1 "ALTER TABLE books
    DROP isbn,
    DROP abstract,
    DROP publisher,
    DROP year,
    DROP typeface,
    DROP edition,
    DROP series;"

c 'Удаление столбцов происходит быстро, поскольку данные фактически не удаляются, а только становятся невидимыми. Поэтому размер таблицы не уменьшится до тех пор, пока строки не будут физически перезаписаны, например, при обновлениях.'

###############################################################################

stop_here
cleanup_app
