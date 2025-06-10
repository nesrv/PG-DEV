#!/bin/bash

. ../lib

init 16

cd
sudo rm -f '/usr/share/postgresql/16/extension/bookfmt--1.0--1.1.sql'

start_here

###############################################################################
h '1. Отчет по складским остаткам'

c 'Начнем с простого запроса, который выводит поступления книг и добавляет к каждой строке количество проданных экземпляров данной книги:'

s 1 "WITH sold(book_id, qty) AS (
    -- продажи книг
    SELECT book_id,
           -sum(qty)
    FROM   operations
    WHERE  qty < 0
    GROUP BY book_id
)
SELECT o.book_id,
       o.qty,
       s.qty as sold_qty,
       o.price
FROM   operations o
     LEFT JOIN sold s ON s.book_id = o.book_id
WHERE  o.qty > 0
AND    o.book_id = 15 -- для примера
ORDER BY o.book_id, o.at;"

c 'Нам хотелось бы иметь функцию, которая на основании столбцов qty и sold_qty вычислит остаток книг от каждого поступления.'

c 'Состояние такой агрегатной функции, которую мы будем использовать в режиме «нарастающего итога», включает два целых числа:'
ul 'количество книг, уже распределенных между поступлениями;'
ul 'количество нераспроданных книг в текущем поступлении.'

s 1 "CREATE TYPE distribute_state AS (
    distributed integer,
    qty integer
);"
c 'Функция перехода увеличивает количество распределенных книг на число книг в поступлении, но только до тех пор, пока оно не превышает общего числа проданных книг:'

s 1 "CREATE FUNCTION distribute_transition(
    state distribute_state,
    qty integer,
    sold_qty integer
)
RETURNS distribute_state
LANGUAGE sql IMMUTABLE
RETURN ROW(
        least(state.distributed + qty, sold_qty),
        qty - (least(state.distributed + qty, sold_qty) - state.distributed)
    )::distribute_state;"

c 'Функция финализации просто возвращает количество нераспроданных книг текущего поступления:'

s 1 "CREATE FUNCTION distribute_final(
    state distribute_state
)
RETURNS integer
LANGUAGE sql IMMUTABLE
RETURN state.qty;"

c 'Создаем агрегат, указав тип состояния и его начальное значение, а также функции перехода и финализации:'

s 1 "CREATE AGGREGATE distribute(qty integer, sold_qty integer) (
    stype     = distribute_state,
    initcond  = '(0,0)',
    sfunc     = distribute_transition,
    finalfunc = distribute_final
);"

c 'Добавим новую агрегатную функцию к запросу, указав группировку по книгам (book_id) и сортировку в порядке времени совершения операций:'

s 1 "WITH sold(book_id, qty) AS (
    -- продажи книг
    SELECT book_id,
           -sum(qty)::integer
    FROM   operations
    WHERE  qty < 0
    GROUP BY book_id
)
SELECT o.book_id,
       o.qty,
       s.qty as sold_qty,
       distribute(o.qty, s.qty) OVER (
           PARTITION BY o.book_id ORDER BY o.at
       ) left_in_stock,
       o.price
FROM   operations o
     LEFT JOIN sold s ON s.book_id = o.book_id
WHERE  o.qty > 0
AND    o.book_id = 15 -- для примера
ORDER BY o.book_id, o.at;"

c 'Осталось убрать условие для конкретной книги, умножить остаток на цену, сгруппировать результат по книгам и оформить запрос в виде функции, чтобы зарегистрировать ее как фоновое задание:'

s 1 "CREATE FUNCTION stock_task(params jsonb DEFAULT NULL)
RETURNS TABLE(book_id bigint, cost numeric)
LANGUAGE sql STABLE
BEGIN ATOMIC
    WITH sold(book_id, qty) AS (
    -- продажи книг
        SELECT book_id, -sum(qty)::integer FROM operations
        WHERE  qty < 0
	GROUP BY book_id
    ), left_in_stock(book_id, cost) AS (
    SELECT o.book_id,
           distribute(o.qty, s.qty) OVER (
	       PARTITION BY o.book_id ORDER BY o.at
           ) * price
    FROM operations o
        LEFT JOIN sold s ON s.book_id = o.book_id
    WHERE  o.qty > 0
)
SELECT book_id, sum(cost) FROM left_in_stock GROUP BY book_id ORDER BY book_id;
END;"


s 1 "SELECT register_program('Отчет по складским остаткам', 'stock_task');"

s 1 "SELECT * FROM stock_task() LIMIT 10;"

c 'Заметим, что задачу можно решить и с помощью стандартных оконных функций:'

s 1 "WITH sold(book_id, qty) AS (
    -- продажи книг
    SELECT book_id,
           -sum(qty)
    FROM   operations
    WHERE  qty < 0
    GROUP BY book_id
), received(book_id, qty, cum_qty, price) AS (
    -- поступления книг
    SELECT book_id,
           qty,
           sum(qty) OVER (PARTITION BY book_id ORDER BY at),
           price
    FROM   operations
    WHERE  qty > 0
), left_in_stock(book_id, qty, price) AS (
    -- оставшиеся на складе книги
    SELECT r.book_id,
           CASE
               WHEN r.cum_qty - s.qty < 0 THEN 0
               WHEN r.cum_qty - s.qty < r.qty THEN r.cum_qty - s.qty
               ELSE r.qty
           END,
           r.price
    FROM   received r
        LEFT JOIN sold s ON s.book_id = r.book_id
)
SELECT book_id,
       sum(qty*price)
FROM   left_in_stock
GROUP BY book_id
ORDER BY book_id
LIMIT 10; -- ограничим вывод"

c 'Разумеется, отчет нетрудно сделать более наглядным, выводя название книги вместо идентификатора.'

###############################################################################
h '2. Min и max для типа book_format'

c 'Сейчас функции min и max работают не в соответствии с определенным ранее классом операторов:'

s 1 "SELECT min(format), max(format) FROM books;"

c 'А вот правильный порядок:'

s 1 "SELECT format FROM books GROUP BY format ORDER BY format;"

c 'Создадим версию 1.1 расширения с учетом следующего:'
ul 'Состоянием для агрегатной функции является текущее минимальное (максимальное) значение.'
ul 'Функция перехода записывает в состояние минимальное (максимальное) из двух значений — запомненного в состоянии и текущего.'
ul 'Функция финализации не нужна — возвращается просто текущее состояние.'

cat >bookfmt/bookfmt.control <<EOF
default_version = '1.1'
relocatable = true
encoding = UTF8
comment = 'Формат издания'
EOF
e "cat bookfmt/bookfmt.control" conf

cat >bookfmt/bookfmt--1.0--1.1.sql <<'EOF'
\echo Use "CREATE EXTENSION bookfmt" to load this file. \quit

CREATE FUNCTION format_min_transition(
    min_so_far book_format,
    val book_format
)
RETURNS book_format
LANGUAGE sql IMMUTABLE
RETURN least(min_so_far, val);


CREATE AGGREGATE min(book_format) (
    stype     = book_format,
    sfunc     = format_min_transition,
    sortop    = <
);

CREATE FUNCTION format_max_transition(
    max_so_far book_format,
    val book_format
)
RETURNS book_format
LANGUAGE sql IMMUTABLE
RETURN greatest(max_so_far, val);


CREATE AGGREGATE max(book_format) (
    stype     = book_format,
    sfunc     = format_max_transition,
    sortop    = >
);
EOF
e "cat bookfmt/bookfmt--1.0--1.1.sql" pgsql

c 'При создании агрегата мы дополнительно указали оператор сортировки, реализующий стратегию «меньше» («больше») класса операторов, чтобы планировщик мог оптимизировать вызов наших агрегатных функций, просто получая первое значение из индекса.'

cat >bookfmt/Makefile <<'EOF'
EXTENSION = bookfmt
DATA = bookfmt--0.sql bookfmt--0--1.0.sql bookfmt--1.0--1.1.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
EOF
e "cat bookfmt/Makefile" sh

e 'sudo make install -C bookfmt'

c 'Выполним обновление:'

s 1 "ALTER EXTENSION bookfmt UPDATE;"

c 'Проверим:'

s 1 "SELECT min(format)::text, max(format)::text FROM books;"
s 1 "SELECT min(format)::text, max(format)::text FROM books WHERE false;"

###############################################################################

stop_here
cleanup_app
