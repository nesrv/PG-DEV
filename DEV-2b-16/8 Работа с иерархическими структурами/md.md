# Работа с иерархическими структурами в PostgreSQL

## Цели

* Ознакомиться с паттернами хранения иерархий в РСБД
* Рассмотреть Adjacency List с рекурсией
* Использовать Materialized Path и `ltree`

---

## 1. Основные паттерны представления иерархий

### 1.1 Adjacency List

* Каждая запись имеет ссылку на родителя

```sql
CREATE TABLE category (
    id serial PRIMARY KEY,
    name text NOT NULL,
    parent_id integer REFERENCES category(id)
);
```

### 1.2 Materialized Path

* Строка с цепочкой id всех предков

```sql
CREATE TABLE category_path (
    id serial PRIMARY KEY,
    name text NOT NULL,
    path text NOT NULL -- e.g. '1.3.8'
);
```

---

## 2. Adjacency List и рекурсия

### 2.1 Вставка данных

```sql
INSERT INTO category (id, name, parent_id) VALUES
(1, 'Electronics', NULL),
(2, 'Computers', 1),
(3, 'Laptops', 2),
(4, 'Smartphones', 1);
```

### 2.2 Рекурсивный запрос

```sql
WITH RECURSIVE category_tree AS (
    SELECT id, name, parent_id, 1 AS level
    FROM category
    WHERE parent_id IS NULL

    UNION ALL

    SELECT c.id, c.name, c.parent_id, ct.level + 1
    FROM category c
    JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT * FROM category_tree ORDER BY level;
```

---

## 3. Materialized Path и ltree

### 3.1 Установка расширения

```sql
CREATE EXTENSION IF NOT EXISTS ltree;
```

### 3.2 Создание таблицы

```sql
CREATE TABLE category_ltree (
    id serial PRIMARY KEY,
    name text NOT NULL,
    path ltree
);
```

### 3.3 Вставка данных

```sql
INSERT INTO category_ltree (name, path) VALUES
('Electronics', 'Electronics'),
('Computers', 'Electronics.Computers'),
('Laptops', 'Electronics.Computers.Laptops'),
('Smartphones', 'Electronics.Smartphones');
```

### 3.4 Поиск потомков

```sql
SELECT * FROM category_ltree
WHERE path <@ 'Electronics.Computers';
```

### 3.5 Поиск предков

```sql
SELECT * FROM category_ltree
WHERE path @> 'Electronics.Computers.Laptops';
```

---

## Выводы

* `Adjacency List` прост для реализации, но требует рекурсивных запросов
* `Materialized Path` легче для отбора по иерархии, но менее гибки
* Расширение `ltree` очень удобно для работы с Materialized Path
