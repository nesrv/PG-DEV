#!/bin/bash

. ../lib

init 9

start_here

###############################################################################
h '1. Розничная цена на книги'

c 'Добавим в таблицу retail_prices столбец с диапазоном дат. Значение по умолчанию — неограниченный диапазон.'

s 1 "ALTER TABLE public.retail_prices
    ADD effective tstzrange NOT NULL DEFAULT '(,)';";

c 'Функция получения текущей цены должна выбрать тот диапазон, в который входит текущая дата:'

s 1 "CREATE OR REPLACE FUNCTION public.get_retail_price(book_id bigint) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER
RETURN (SELECT rp.price
	FROM retail_prices rp
        WHERE rp.book_id = get_retail_price.book_id
	    AND rp.effective @> current_timestamp);"

c 'Функция установки цены должна изменить одну строку и добавить одну новую. Использование уровня изоляции Read Committed в этом случае может приводить к аномалиям, поэтому сначала заблокируем соответствующую запись в таблице books, чтобы в один момент времени только одна транзакция могла устанавливать цену одной и той же книги.'

s 1 "CREATE OR REPLACE FUNCTION empapi.set_retail_price (
    book_id bigint,
    price numeric,
    at timestamptz
)
RETURNS void
AS \$\$
DECLARE
    lower_bound timestamptz;
    upper_bound timestamptz;
BEGIN
    PERFORM FROM books b
    WHERE b.book_id = set_retail_price.book_id
    FOR UPDATE;

    SELECT lower(rp.effective), upper(rp.effective)
    INTO lower_bound, upper_bound
    FROM retail_prices rp
    WHERE rp.book_id = set_retail_price.book_id
      AND at <@ rp.effective;

    IF at = lower_bound THEN
        -- только обновляем цену в существующем диапазоне
        UPDATE retail_prices rp
        SET price = set_retail_price.price
        WHERE rp.book_id = set_retail_price.book_id
          AND at <@ rp.effective
        ;
    ELSE
        -- закрываем существующий диапазон...
        UPDATE retail_prices rp
        SET effective = tstzrange(lower_bound, at, '[)')
        WHERE rp.book_id = set_retail_price.book_id
          AND at <@ rp.effective;
        -- ...и добавляем новый
        INSERT INTO retail_prices (
            book_id,
            price,
            effective
        ) VALUES (
            book_id,
            price,
            tstzrange(at, upper_bound, '[)')
        );
    END IF;
END;
\$\$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;"

c 'Проверим.'

s 1 "BEGIN;"

s 1 "SELECT * FROM retail_prices WHERE book_id = 1 ORDER BY effective;"

c 'Вставка новой цены в конец:'

export CUR1=`sudo -i -u $OSUSER psql -A -t -X -d bookstore2 -c "SELECT date_trunc('minute',current_timestamp)"`
export CUR2=`sudo -i -u $OSUSER psql -A -t -X -d bookstore2 -c "SELECT date_trunc('minute',current_timestamp + interval '1 days')"`
s 1 "SELECT empapi.set_retail_price(1, 200.00, '$CUR2');"
s 1 "SELECT * FROM retail_prices WHERE book_id = 1 ORDER BY effective;"

c 'Вставка не в конец:'

s 1 "SELECT empapi.set_retail_price(1, 300.00, '$CUR1');"
s 1 "SELECT * FROM retail_prices WHERE book_id = 1 ORDER BY effective;"

c 'Цена с уже существующей датой (новый интервал не появляется):'

s 1 "SELECT empapi.set_retail_price(1, 400.00, '$CUR1');"
s 1 "SELECT * FROM retail_prices WHERE book_id = 1 ORDER BY effective;"

s 1 "ROLLBACK;"

###############################################################################
h '2. Тип данных для формата издания'

c 'Тип данных:'

s 1 "CREATE TYPE book_format AS (
   width integer,
   height integer,
   parts integer 
);"

c 'Преобразование в текст:'

s 1 "CREATE FUNCTION book_format_to_text(f book_format) RETURNS text
LANGUAGE sql STRICT IMMUTABLE
RETURN f.width || 'x' || f.height || '/' || f.parts;"

s 1 "CREATE CAST (book_format AS text)
WITH FUNCTION book_format_to_text AS IMPLICIT;"

c 'Проверим:'

s 1 "SELECT (90,60,16)::book_format::text;"

c 'И обратно:'

s 1 "CREATE FUNCTION text_to_book_format(f text) RETURNS book_format
LANGUAGE sql STRICT IMMUTABLE
RETURN (SELECT (m[1],m[2],m[3])::book_format
	FROM regexp_match(f, '(\\d+)x(\\d+)/(\\d+)') m);"

s 1 "CREATE CAST (text AS book_format)
WITH FUNCTION text_to_book_format AS IMPLICIT;"

c 'Проверим:'

s 1 "SELECT '90x60/16'::text::book_format;"

c 'Обратите внимание, что если написать просто:'

s 1 "SELECT '90x60/16'::book_format;"

c 'то произойдет ошибка: здесь срабатывает не приведение типа text в book_format, а создание типа book_format из литерала, которое использует фиксированный формат для всех составных типов:'

s 1 "SELECT '(90,60,16)'::book_format;"

c 'Теперь заменим тип столбца. Это тяжелая операция, которая перезаписывает всю таблицу, полностью блокируя работу с ней. Поэтому использовать ее надо с осторожностью, особенно для больших таблиц.'

c 'Вот в каком файле находятся данные сейчас:'

s 1 "SELECT pg_relation_filepath('books');"

c 'Выполняем замену типа. Преобразование будет выполнено автоматически благодаря созданному ранее приведению типов:'

s 1 "BEGIN;"

s 1 "ALTER TABLE books ALTER COLUMN format SET DATA TYPE book_format;"

s 1 "SELECT relation::regclass, mode
FROM pg_locks
WHERE relation = 'books'::regclass;"

c 'Операция выполняется в несколько шагов, но при перезаписи таблицы используется исключительная блокировка.'

c 'В этой же транзакции надо внести изменения и в интерфейсные функции приложения. Формат возвращают две функции: webapi.get_catalog и empapi.get_catalog, но обе они вызывают одну и ту же функцию public.get_catalog. К счастью, в этой функции столбец format явно приводится к типу text, поэтому никаких изменений не требуется.'

s 1 "COMMIT;"

c 'Теперь данные таблицы находятся в другом файле:'

s 1 "SELECT pg_relation_filepath('books');"

###############################################################################

stop_here
cleanup_app
