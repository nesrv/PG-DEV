# BOOKSTORE





## Исходные данные для БД


[Логическая копия bookstore.sql](present/DAY-6/bookstore.sql)


[Исходники для bookstore source_bookstore.sql](present/DAY-6/source_bookstore.sql)


```bash
-- подключаемся в постгрес в докер-контейнере
psql -h localhost -p 5434 -U postgres -d bookstore 
-- создаем БД bookstore
createdb -U postgres -h localhost -p 5434 bookstore

-- восстанавливаем БД bookstore из файла bookstore.sql
psql -U postgres -h localhost -p 5434 -d bookstore -f bookstore.sql

-- как сделать простой sql-дамп базы bookstore
pg_dump -d bookstore -f bookstore.sql


```


```sql

```


```bash

```