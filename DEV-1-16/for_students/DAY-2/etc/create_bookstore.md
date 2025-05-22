## 1. Схема и путь поиска


```sql
CREATE DATABASE bookstore;
```

```sh
\c bookstore
```

```sql
CREATE SCHEMA bookstore;
```

```sql
ALTER DATABASE bookstore SET search_path = bookstore, public;
```

```sh
\c
```

```sh
SHOW search_path;
```



## 2. Таблицы

> Авторы:

```sql
CREATE TABLE authors(
author_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
last_name text NOT NULL,
first_name text NOT NULL,
middle_name text
);
```


> Книги:

```sql
CREATE TABLE books(
book_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
title text NOT NULL
);
```

```sql
CREATE TABLE authorship(
book_id integer REFERENCES books,
author_id integer REFERENCES authors,
seq_num integer NOT NULL,
PRIMARY KEY (book_id,author_id)
);
```

> Операции:

```sql
CREATE TABLE operations(
operation_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
book_id integer NOT NULL REFERENCES books,
qty_change integer NOT NULL,
date_created date NOT NULL DEFAULT current_date
);
```

## Данные

> Авторы:

```sql
INSERT INTO authors(last_name, first_name, middle_name)
VALUES
('Пушкин', 'Александр', 'Сергеевич'),
('Тургенев', 'Иван', 'Сергеевич'),
('Стругацкий', 'Борис', 'Натанович'),
('Стругацкий', 'Аркадий', 'Натанович'),
('Толстой', 'Лев', 'Николаевич'),
('Свифт', 'Джонатан', NULL);
```

> Книги:

```sql
INSERT INTO books(title)
VALUES
('Сказка о царе Салтане'),
('Муму'),
('Трудно быть богом'),
('Война и мир'),
('Путешествия в некоторые удаленные страны мира в четырех частях: сочинение Лемюэля Гулливера, сначала хирурга, а затем капитана нескольких кораблей'),
('Хрестоматия');
```

> Авторство:

```sql
INSERT INTO authorship(book_id, author_id, seq_num)
VALUES
(1, 1, 1),
(2, 2, 1),
(3, 3, 2),
(3, 4, 1),
(4, 5, 1),
(5, 6, 1),
(6, 1, 1),
(6, 5, 2),
(6, 2, 3);
```

## Операции:

```sql

INSERT INTO operations(book_id, qty_change)
VALUES
(1, 10),
(1, 10),
(1, -1);
```

## 4. Представления

> Представление для авторов:

```sql
CREATE VIEW authors_v AS
SELECT a.author_id,
    a.last_name || ' ' ||
    a.first_name ||
    coalesce(' ' || nullif(a.middle_name, ''), '') AS display_name
FROM authors a;
```

> Представление для каталога:

```sql
CREATE VIEW catalog_v AS
SELECT b.book_id,
       b.title AS display_name
FROM books b;
```

> Представление для операций:

```sql
CREATE VIEW operations_v AS
SELECT book_id,
    CASE
        WHEN qty_change > 0 THEN 'Поступление'
        ELSE 'Покупка'
    END op_type,
    abs(qty_change) qty_change,
    to_char(date_created, 'DD.MM.YYYY') date_created
FROM operations
ORDER BY operation_id;
```




## PS

```sql
SELECT COALESCE(null, 8, 9, null, 10 );
```


```sql
SELECT first_name, COALESCE(email,'None') from Employee; 
```

> ошибка

```sql
SELECT COALESCE(NULL, 6, 'A');
```