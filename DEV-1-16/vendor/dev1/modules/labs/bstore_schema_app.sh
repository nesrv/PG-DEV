#!/bin/bash

. ../lib

init_app
psql_open A 1

s 1 'DROP DATABASE IF EXISTS bookstore (FORCE);'
s 1 'DROP ROLE IF EXISTS employee;'
s 1 'DROP ROLE IF EXISTS buyer;'

start_here

###############################################################################
h '1. Схема и путь поиска'

s 1 'CREATE DATABASE bookstore;' # изначально нет в ВМ
s 1 '\c bookstore'

s 1 'CREATE SCHEMA bookstore;'

s 1 'ALTER DATABASE bookstore SET search_path = bookstore, public;'
s 1 '\c'
s 1 'SHOW search_path;'

###############################################################################
h '2. Таблицы'

c 'Авторы:'

s 1 "CREATE TABLE authors(
    author_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    last_name text NOT NULL,
    first_name text NOT NULL,
    middle_name text
);"

c 'Книги:'

s 1 "CREATE TABLE books(
    book_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    title text NOT NULL
);"

c 'Авторство:'

s 1 "CREATE TABLE authorship(
    book_id integer REFERENCES books,
    author_id integer REFERENCES authors,
    seq_num integer NOT NULL,
    PRIMARY KEY (book_id,author_id)
);"

c 'Операции:'

s 1 "CREATE TABLE operations(
    operation_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    book_id integer NOT NULL REFERENCES books,
    qty_change integer NOT NULL,
    date_created date NOT NULL DEFAULT current_date
);"

###############################################################################
h '3. Данные'

c 'Авторы:'

s 1 "INSERT INTO authors(last_name, first_name, middle_name)
VALUES 
    ('Пушкин', 'Александр', 'Сергеевич'),
    ('Тургенев', 'Иван', 'Сергеевич'),
    ('Стругацкий', 'Борис', 'Натанович'),
    ('Стругацкий', 'Аркадий', 'Натанович'),
    ('Толстой', 'Лев', 'Николаевич'),
    ('Свифт', 'Джонатан', NULL);"

c 'Книги:'

s 1 "INSERT INTO books(title)
VALUES
    ('Сказка о царе Салтане'),
    ('Муму'),
    ('Трудно быть богом'),
    ('Война и мир'),
    ('Путешествия в некоторые удаленные страны мира в четырех частях: сочинение Лемюэля Гулливера, сначала хирурга, а затем капитана нескольких кораблей'),
    ('Хрестоматия');"

c 'Авторство:'

s 1 "INSERT INTO authorship(book_id, author_id, seq_num) 
VALUES
    (1, 1, 1),
    (2, 2, 1),
    (3, 3, 2),
    (3, 4, 1),
    (4, 5, 1),
    (5, 6, 1),
    (6, 1, 1),
    (6, 5, 2),
    (6, 2, 3);"

c 'Операции:'

s 1 "INSERT INTO operations(book_id, qty_change)
VALUES
    (1, 10),
    (1, 10),
    (1, -1);"


###############################################################################
h '4. Представления'

c 'Представление для авторов:'

s 1 "CREATE VIEW authors_v AS
SELECT a.author_id,
       a.last_name || ' ' ||
       a.first_name ||
       coalesce(' ' || nullif(a.middle_name, ''), '') AS display_name
FROM   authors a;"

c 'Представление для каталога:'

s 1 "CREATE VIEW catalog_v AS
SELECT b.book_id,
       b.title AS display_name
FROM   books b;"

c 'Представление для операций:'

s 1 "CREATE VIEW operations_v AS
SELECT book_id,
       CASE
           WHEN qty_change > 0 THEN 'Поступление'
           ELSE 'Покупка'
       END op_type, 
       abs(qty_change) qty_change, 
       to_char(date_created, 'DD.MM.YYYY') date_created
FROM   operations
ORDER BY operation_id;"

###############################################################################

stop_here
cleanup_app
