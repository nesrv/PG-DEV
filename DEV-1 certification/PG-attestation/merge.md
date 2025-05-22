

## Операции INSERT, UPDATE и DELETE с помощью оператора "MERGE". Синтаксис и основные элементы


# Использование оператора MERGE в PostgreSQL для INSERT, UPDATE и DELETE

Оператор MERGE (также известный как "upsert") в PostgreSQL позволяет выполнять операции INSERT, UPDATE и DELETE в одном выражении, что очень удобно для синхронизации данных между таблицами.

## Основной синтаксис MERGE

```sql
MERGE INTO target_table USING source_table
ON merge_condition
WHEN MATCHED THEN
    UPDATE SET column1 = value1, column2 = value2, ...
    [DELETE WHERE condition]
WHEN NOT MATCHED THEN
    INSERT (column1, column2, ...) VALUES (value1, value2, ...);
```

## Примеры использования

### 1. Базовый пример с INSERT и UPDATE

```sql
-- Создаем тестовые таблицы
CREATE TABLE target_products (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(100),
    price DECIMAL(10, 2),
    quantity INT
);

CREATE TABLE source_products (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(100),
    price DECIMAL(10, 2),
    quantity INT
);

-- Вставляем начальные данные
INSERT INTO target_products VALUES 
(1, 'Laptop', 999.99, 10),
(2, 'Phone', 499.99, 20);

INSERT INTO source_products VALUES 
(1, 'Laptop', 899.99, 15), -- Обновим цену и количество
(3, 'Tablet', 299.99, 30); -- Новый товар

-- Выполняем MERGE
MERGE INTO target_products t
USING source_products s
ON t.product_id = s.product_id
WHEN MATCHED THEN
    UPDATE SET 
        product_name = s.product_name,
        price = s.price,
        quantity = s.quantity
WHEN NOT MATCHED THEN
    INSERT (product_id, product_name, price, quantity)
    VALUES (s.product_id, s.product_name, s.price, s.quantity);
```

### 2. Пример с DELETE условием

```sql
-- Добавим условие для удаления
MERGE INTO target_products t
USING source_products s
ON t.product_id = s.product_id
WHEN MATCHED AND s.quantity = 0 THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET 
        product_name = s.product_name,
        price = s.price,
        quantity = s.quantity
WHEN NOT MATCHED THEN
    INSERT (product_id, product_name, price, quantity)
    VALUES (s.product_id, s.product_name, s.price, s.quantity);
```

### 3. Пример с подзапросом в качестве источника

```sql
-- MERGE с подзапросом вместо таблицы
MERGE INTO target_products t
USING (
    SELECT product_id, product_name, price, quantity 
    FROM source_products 
    WHERE price > 300
) s
ON t.product_id = s.product_id
WHEN MATCHED THEN
    UPDATE SET 
        product_name = s.product_name,
        price = s.price,
        quantity = s.quantity
WHEN NOT MATCHED THEN
    INSERT (product_id, product_name, price, quantity)
    VALUES (s.product_id, s.product_name, s.price, s.quantity);
```

### 4. Пример с несколькими условиями

```sql
MERGE INTO target_products t
USING source_products s
ON t.product_id = s.product_id
WHEN MATCHED AND t.price > s.price THEN
    UPDATE SET price = s.price -- Обновляем только если цена в источнике ниже
WHEN MATCHED AND t.price <= s.price THEN
    DO NOTHING -- Ничего не делаем, если цена в источнике выше или равна
WHEN NOT MATCHED THEN
    INSERT (product_id, product_name, price, quantity)
    VALUES (s.product_id, s.product_name, s.price, s.quantity);
```

## Важные заметки

1. Оператор MERGE был добавлен в PostgreSQL начиная с версии 15.
2. MERGE выполняется как единая атомарная операция.
3. Можно использовать несколько WHEN MATCHED и WHEN NOT MATCHED условий, но порядок имеет значение.
4. Для более старых версий PostgreSQL можно использовать INSERT ... ON CONFLICT (UPSERT) для аналогичной функциональности.

MERGE особенно полезен при:
- Синхронизации таблиц
- Пакетных обновлениях данных
- Реализации сложной бизнес-логики обновлений


## Операторы ветвления логики. "DECODE", "CASE WHEN"(2 способа). Синтаксис и основные элементы.

# Операторы ветвления логики в PostgreSQL

PostgreSQL предоставляет несколько операторов для ветвления логики в SQL-запросах. Рассмотрим основные из них: DECODE и CASE WHEN (в двух вариантах).

## 1. DECODE

DECODE - это функция, аналогичная CASE WHEN, но с другим синтаксисом (унаследована из Oracle).

### Синтаксис:
```sql
DECODE(выражение, значение1, результат1, 
                   значение2, результат2, 
                   ...
                   значениеN, результатN, 
                   default_результат)
```

### Пример:
```sql
SELECT product_name, 
       DECODE(category_id, 1, 'Electronics', 
                           2, 'Clothing', 
                           3, 'Food', 
                           'Other') AS category_name
FROM products;
```

## 2. CASE WHEN (два варианта)

### Вариант 1: Простое CASE выражение

Аналогично DECODE, но с другим синтаксисом.

#### Синтаксис:
```sql
CASE выражение
    WHEN значение1 THEN результат1
    WHEN значение2 THEN результат2
    ...
    WHEN значениеN THEN результатN
    ELSE default_результат
END
```

#### Пример:
```sql
SELECT product_name, 
       CASE category_id
           WHEN 1 THEN 'Electronics'
           WHEN 2 THEN 'Clothing'
           WHEN 3 THEN 'Food'
           ELSE 'Other'
       END AS category_name
FROM products;
```

### Вариант 2: Поисковое CASE выражение

Более гибкий вариант, позволяющий использовать условия.

#### Синтаксис:
```sql
CASE
    WHEN условие1 THEN результат1
    WHEN условие2 THEN результат2
    ...
    WHEN условиеN THEN результатN
    ELSE default_результат
END
```

#### Пример:
```sql
SELECT product_name, price,
       CASE
           WHEN price < 100 THEN 'Cheap'
           WHEN price >= 100 AND price < 500 THEN 'Medium'
           WHEN price >= 500 THEN 'Expensive'
           ELSE 'Not priced'
       END AS price_category
FROM products;
```

## Основные элементы:

1. **Выражение/условие** - то, что оценивается для выбора ветви
2. **THEN** - определяет результат при выполнении условия
3. **ELSE** - необязательный элемент, определяющий результат по умолчанию
4. **END** - обязательное завершение CASE выражения

## Особенности в PostgreSQL:

- DECODE не является стандартной функцией SQL, но доступна в PostgreSQL через расширение oracle_fdw
- CASE WHEN является стандартным SQL и предпочтительнее для использования
- CASE выражения могут использоваться в SELECT, WHERE, GROUP BY, ORDER BY и других частях запроса
- Можно вкладывать CASE выражения друг в друга для сложной логики


