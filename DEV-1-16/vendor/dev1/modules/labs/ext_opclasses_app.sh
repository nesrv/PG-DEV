#!/bin/bash

. ../lib

init 10

start_here

###############################################################################
h '1. Ограничение целостности для retail_prices'

c 'Добавим ограничение целостности в таблицу:'

s 1 "CREATE EXTENSION btree_gist;"
s 1 "ALTER TABLE retail_prices ADD
    EXCLUDE USING gist(book_id WITH =, effective WITH &&);"

c 'Такое ограничение гарантирует, что данные не будет повреждены, даже если в коде функции set_retail_price будет допущена ошибка.'

c 'В функции get_retail_price используется запрос следующего вида:'

s 1 "EXPLAIN (costs off)
SELECT rp.price
FROM retail_prices rp
WHERE rp.book_id = 1
  AND rp.effective @> current_timestamp;"

c 'Как видно из плана, таблица по-прежнему перебирается полностью. Но планировщик будет использовать созданный индекс, как только это окажется выгодным:'

s 1 "BEGIN;"

s 1 "WITH s AS (
    SELECT empapi.set_retail_price(
               b.book_id, 100.00, current_timestamp
           ),
           empapi.set_retail_price(
               b.book_id, 200.00, current_timestamp + interval '1 day'
           ),
           empapi.set_retail_price(
               b.book_id, 300.00, current_timestamp + interval '2 days'
           )
    FROM books b
)
SELECT count(*) FROM s;"

s 1 "EXPLAIN (costs off)
SELECT rp.price
FROM retail_prices rp
WHERE rp.book_id = 1
  AND rp.effective @> current_timestamp;"

s 1 "ROLLBACK;"

###############################################################################
h '2. Упорядочивание для форматов издания'

c 'Создадим класс операторов, как было показано в демонстрации.'

s 1 "CREATE FUNCTION book_format_area(f book_format) RETURNS numeric
LANGUAGE sql STRICT IMMUTABLE
RETURN f.width::numeric * f.height::numeric / f.parts::numeric;"

s 1 "CREATE FUNCTION book_format_cmp(a book_format, b book_format) RETURNS integer
LANGUAGE sql STRICT IMMUTABLE
RETURN
CASE
    WHEN book_format_area(a) < book_format_area(b) THEN -1
    WHEN book_format_area(a) > book_format_area(b) THEN 1
    ELSE 0
END;"

s 1 "CREATE FUNCTION book_format_lt(a book_format, b book_format) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN book_format_cmp(a,b) < 0;"

s 1 "CREATE OPERATOR <(
    LEFTARG = book_format,
    RIGHTARG = book_format,
    FUNCTION = book_format_lt
);"

s 1 "CREATE FUNCTION book_format_le(a book_format, b book_format) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN book_format_cmp(a,b) <= 0;"

s 1 "CREATE OPERATOR <=(
    LEFTARG = book_format,
    RIGHTARG = book_format,
    FUNCTION = book_format_le
);"

s 1 "CREATE FUNCTION book_format_eq(a book_format, b book_format) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN book_format_cmp(a,b) = 0;"

s 1 "CREATE OPERATOR =(
    LEFTARG = book_format,
    RIGHTARG = book_format,
    FUNCTION = book_format_eq
);"

s 1 "CREATE FUNCTION book_format_ge(a book_format, b book_format) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN book_format_cmp(a,b) >= 0;"

s 1 "CREATE OPERATOR >=(
    LEFTARG = book_format,
    RIGHTARG = book_format,
    FUNCTION = book_format_ge
);"

s 1 "CREATE FUNCTION book_format_gt(a book_format, b book_format) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN book_format_cmp(a,b) > 0;"

s 1 "CREATE OPERATOR >(
    LEFTARG = book_format,
    RIGHTARG = book_format,
    FUNCTION = book_format_gt
);"

s 1 "CREATE OPERATOR CLASS book_format_ops
DEFAULT FOR TYPE book_format
USING btree AS
    OPERATOR 1 <,
    OPERATOR 2 <=,
    OPERATOR 3 =,
    OPERATOR 4 >=,
    OPERATOR 5 >,
    FUNCTION 1 book_format_cmp(book_format,book_format);"

c 'Все готово. Проверим:'

s 1 "SELECT format FROM books GROUP BY format ORDER BY format;"

###############################################################################

stop_here
cleanup_app
