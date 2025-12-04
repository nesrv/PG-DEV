# Операции с данными (CRUD)

## Подготовка: Создание тестовых таблиц

```sql
-- Создаем базу данных
CREATE DATABASE shop_example;
\c shop_example

-- Таблица категорий
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

-- Таблица товаров
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    stock_quantity INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица клиентов
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(20),
    birth_date DATE,
    city VARCHAR(50)
);
```

## 1. Добавление данных (INSERT)

### Примеры INSERT

```sql
-- Простая вставка
INSERT INTO categories (name, description) 
VALUES ('Электроника', 'Электронные устройства');

-- Множественная вставка
INSERT INTO categories (name, description) VALUES
('Книги', 'Художественная и техническая литература'),
('Одежда', 'Мужская и женская одежда'),
('Спорт', 'Спортивные товары и инвентарь');

-- Вставка с автоинкрементом (пропускаем id)
INSERT INTO products (name, price, category_id, stock_quantity) VALUES
('iPhone 15', 89990.00, 1, 25),
('Samsung Galaxy', 79990.00, 1, 30),
('Учебник SQL', 1500.00, 2, 100),
('Футболка Nike', 2500.00, 3, 50);

-- Вставка клиентов
INSERT INTO customers (first_name, last_name, email, phone, birth_date, city) VALUES
('Иван', 'Петров', 'ivan@email.com', '+7-900-123-4567', '1985-03-15', 'Москва'),
('Мария', 'Сидорова', 'maria@email.com', '+7-900-234-5678', '1990-07-22', 'СПб'),
('Алексей', 'Козлов', 'alex@email.com', '+7-900-345-6789', '1988-11-08', 'Екатеринбург');
```

### Задачи INSERT

**Задача 1:** Добавьте 3 новых товара в категорию "Спорт"

```sql
-- Решение:
INSERT INTO products (name, price, category_id, stock_quantity) VALUES
('Мяч футбольный', 1200.00, 4, 20),
('Гантели 5кг', 3500.00, 4, 15),
('Коврик для йоги', 800.00, 4, 40);
```

**Задача 2:** Добавьте клиента только с именем и email

```sql
-- Решение:
INSERT INTO customers (first_name, last_name, email) 
VALUES ('Елена', 'Морозова', 'elena@email.com');
```

## 2. Получение данных (SELECT)

### Примеры SELECT

```sql
-- Выбрать все записи
SELECT * FROM products;

-- Выбрать определенные столбцы
SELECT name, price FROM products;

-- Выбрать с псевдонимами
SELECT 
    name AS product_name,
    price AS cost,
    stock_quantity AS in_stock
FROM products;

-- Выбрать с вычислениями
SELECT 
    name,
    price,
    price * 0.9 AS discounted_price,
    stock_quantity * price AS total_value
FROM products;

-- Выбрать уникальные значения
SELECT DISTINCT city FROM customers;

-- Выбрать с сортировкой
SELECT name, price FROM products ORDER BY price DESC;

-- Выбрать с ограничением
SELECT name, price FROM products ORDER BY price DESC LIMIT 3;
```

### Задачи SELECT

**Задача 3:** Выведите названия и цены товаров, отсортированные по цене по возрастанию

```sql
-- Решение:
SELECT name, price FROM products ORDER BY price ASC;
```

**Задача 4:** Выведите имена клиентов и их города, только уникальные города

```sql
-- Решение:
SELECT first_name, last_name, city FROM customers WHERE city IS NOT NULL;
SELECT DISTINCT city FROM customers WHERE city IS NOT NULL;
```

## 3. Фильтрация (WHERE)

### Примеры WHERE

```sql
-- Простое условие
SELECT * FROM products WHERE price > 5000;

-- Несколько условий
SELECT * FROM products WHERE price > 1000 AND stock_quantity > 20;

-- Условие ИЛИ
SELECT * FROM customers WHERE city = 'Москва' OR city = 'СПб';

-- Условие IN
SELECT * FROM customers WHERE city IN ('Москва', 'СПб', 'Екатеринбург');

-- Условие BETWEEN
SELECT * FROM products WHERE price BETWEEN 1000 AND 10000;

-- Условие LIKE (поиск по шаблону)
SELECT * FROM products WHERE name LIKE '%iPhone%';
SELECT * FROM customers WHERE first_name LIKE 'И%';

-- Условие IS NULL / IS NOT NULL
SELECT * FROM customers WHERE phone IS NOT NULL;

-- Условие с датами
SELECT * FROM customers WHERE birth_date > '1987-01-01';
```

### Задачи WHERE

**Задача 5:** Найдите всех клиентов, родившихся после 1985 года и живущих в Москве

```sql
-- Решение:
SELECT * FROM customers 
WHERE birth_date > '1987-01-01' AND city = 'Москва';
```

**Задача 6:** Найдите товары, в названии которых есть слово "Samsung" или цена меньше 2000

```sql
-- Решение:
SELECT * FROM products 
WHERE name LIKE '%Samsung%' OR price < 2000;
```

## 4. Обновление данных (UPDATE)

### Примеры UPDATE

```sql
-- Обновить одно поле
UPDATE products SET price = 85000.00 WHERE name = 'iPhone 15';

-- Обновить несколько полей
UPDATE products 
SET price = 75000.00, stock_quantity = 35 
WHERE name = 'Samsung Galaxy';

-- Обновить с вычислением
UPDATE products SET price = price * 1.1 WHERE category_id = 1;

-- Обновить с условием
UPDATE customers 
SET city = 'Москва' 
WHERE city IS NULL AND phone LIKE '+7-495%';

-- Обновить с подзапросом
UPDATE products 
SET is_active = FALSE 
WHERE category_id = (SELECT id FROM categories WHERE name = 'Книги');
```

### Задачи UPDATE

**Задача 7:** Увеличьте цены всех товаров в категории "Спорт" на 15%

```sql
-- Решение:
UPDATE products 
SET price = price * 1.15 
WHERE category_id = (SELECT id FROM categories WHERE name = 'Спорт');
```

**Задача 8:** Обновите email клиента Ивана Петрова на 'ivan.petrov@newmail.com'

```sql
-- Решение:
UPDATE customers 
SET email = 'ivan.petrov@newmail.com' 
WHERE first_name = 'Иван' AND last_name = 'Петров';
```

## 5. Удаление данных (DELETE)

### Примеры DELETE

```sql
-- Удалить по условию
DELETE FROM products WHERE stock_quantity = 0;

-- Удалить с несколькими условиями
DELETE FROM customers WHERE city IS NULL AND phone IS NULL;

-- Удалить с подзапросом
DELETE FROM products 
WHERE category_id = (SELECT id FROM categories WHERE name = 'Устаревшие');

-- Удалить все записи (осторожно!)
-- DELETE FROM temp_table;

-- Безопасное удаление с LIMIT (в некоторых СУБД)
DELETE FROM products WHERE is_active = FALSE LIMIT 5;
```

### Задачи DELETE

**Задача 9:** Удалите всех клиентов без email

```sql
-- Решение:
DELETE FROM customers WHERE email IS NULL;
```

**Задача 10:** Удалите товары дешевле 1000 рублей

```sql
-- Решение:
DELETE FROM products WHERE price < 1000;
```

## 6. Импорт-экспорт данных

### Экспорт в CSV

```sql
-- Экспорт всех товаров
\copy products TO 'products_export.csv' CSV HEADER;
-- windows
\copy products TO 'C:\temp\products_export.csv' CSV HEADER;

-- Экспорт с условием
\copy (SELECT name, price, stock_quantity FROM products WHERE is_active = TRUE) TO 'active_products.csv' CSV HEADER;

-- Экспорт клиентов
\copy customers TO 'customers_backup.csv' CSV HEADER;
```

### Импорт из CSV

```sql
-- Создаем временную таблицу для импорта
CREATE TABLE temp_products (
    name VARCHAR(100),
    price DECIMAL(10,2),
    category_name VARCHAR(100),
    stock_quantity INTEGER
);

-- Импорт из CSV
\copy temp_products FROM 'new_products.csv' CSV HEADER;

-- Перенос данных в основную таблицу
INSERT INTO products (name, price, category_id, stock_quantity)
SELECT 
    tp.name, 
    tp.price, 
    c.id, 
    tp.stock_quantity
FROM temp_products tp
JOIN categories c ON c.name = tp.category_name;
```

### Работа с текстовыми файлами

```sql
-- Создание файла с данными
\copy (SELECT first_name || ' ' || last_name AS full_name, email, city FROM customers) TO 'customer_list.txt' WITH (FORMAT text, DELIMITER E'\t');

-- Импорт из текстового файла
CREATE TABLE imported_data (
    full_name TEXT,
    email TEXT,
    city TEXT
);

\copy imported_data FROM 'customer_list.txt' WITH (FORMAT text, DELIMITER E'\t');
```

### Задачи импорт-экспорт

**Задача 11:** Экспортируйте список товаров дороже 5000 рублей в файл expensive_products.csv

```sql
-- Решение:
\copy (SELECT name, price, stock_quantity FROM products WHERE price > 5000) TO 'expensive_products.csv' CSV HEADER;
```

**Задача 12:** Создайте отчет по клиентам в текстовом формате

```sql
-- Решение:
\copy (SELECT 
    first_name || ' ' || last_name AS "ФИО",
    email AS "Email",
    COALESCE(city, 'Не указан') AS "Город"
FROM customers 
ORDER BY last_name) TO 'customers_report.txt' WITH (FORMAT text, DELIMITER '|', HEADER);
```

## 7. Группировка и фильтрация групп (GROUP BY и HAVING)

### Создание дополнительных данных для примеров

```sql
-- Добавим таблицу заказов
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    order_date DATE DEFAULT CURRENT_DATE,
    total_amount DECIMAL(10,2)
);

-- Заполним заказами
INSERT INTO orders (customer_id, product_id, quantity, total_amount, order_date) VALUES
(1, 1, 1, 89990.00, '2023-01-15'),
(1, 3, 2, 3000.00, '2023-01-20'),
(2, 2, 1, 79990.00, '2023-02-10'),
(2, 4, 3, 7500.00, '2023-02-15'),
(3, 1, 2, 179980.00, '2023-03-05'),
(1, 4, 1, 2500.00, '2023-03-10'),
(2, 3, 1, 1500.00, '2023-03-15');
```

### Примеры GROUP BY

```sql
-- Количество товаров по категориям
SELECT 
    c.name as category_name,
    COUNT(p.id) as product_count
FROM categories c
LEFT JOIN products p ON c.id = p.category_id
GROUP BY c.id, c.name;

-- Общая сумма заказов по клиентам
SELECT 
    customer_id,
    COUNT(*) as order_count,
    SUM(total_amount) as total_spent
FROM orders
GROUP BY customer_id;

-- Средняя цена товаров по категориям
SELECT 
    c.name as category_name,
    AVG(p.price) as avg_price,
    MIN(p.price) as min_price,
    MAX(p.price) as max_price
FROM categories c
JOIN products p ON c.id = p.category_id
GROUP BY c.id, c.name;
```

### Примеры HAVING

```sql
-- Клиенты с общей суммой заказов больше 50000
SELECT 
    customer_id,
    COUNT(*) as order_count,
    SUM(total_amount) as total_spent
FROM orders
GROUP BY customer_id
HAVING SUM(total_amount) > 50000;

-- Категории с количеством товаров больше 1
SELECT 
    c.name as category_name,
    COUNT(p.id) as product_count
FROM categories c
LEFT JOIN products p ON c.id = p.category_id
GROUP BY c.id, c.name
HAVING COUNT(p.id) > 1;

-- Клиенты с количеством заказов больше 2 И средним чеком больше 10000
SELECT 
    customer_id,
    COUNT(*) as order_count,
    AVG(total_amount) as avg_order,
    SUM(total_amount) as total_spent
FROM orders
GROUP BY customer_id
HAVING COUNT(*) > 2 AND AVG(total_amount) > 10000;
```

### Задачи GROUP BY и HAVING

**Задача 15:** Найдите категории со средней ценой товаров больше 5000

```sql
-- Решение:
SELECT 
    c.name as category_name,
    AVG(p.price) as avg_price,
    COUNT(p.id) as product_count
FROM categories c
JOIN products p ON c.id = p.category_id
GROUP BY c.id, c.name
HAVING AVG(p.price) > 5000;
```

**Задача 16:** Найдите клиентов, которые сделали больше 1 заказа

```sql
-- Решение:
SELECT 
    c.first_name,
    c.last_name,
    COUNT(o.id) as order_count,
    SUM(o.total_amount) as total_spent
FROM customers c
JOIN orders o ON c.id = o.customer_id
GROUP BY c.id, c.first_name, c.last_name
HAVING COUNT(o.id) > 1;
```

**Задача 17:** Найдите месяцы 2023 года с общей суммой заказов больше 100000

```sql
-- Решение:
SELECT 
    EXTRACT(MONTH FROM order_date) as month,
    COUNT(*) as order_count,
    SUM(total_amount) as monthly_total
FROM orders
WHERE EXTRACT(YEAR FROM order_date) = 2023
GROUP BY EXTRACT(MONTH FROM order_date)
HAVING SUM(total_amount) > 100000
ORDER BY month;
```

### Сложные примеры с HAVING

```sql
-- Анализ активности клиентов
SELECT 
    c.first_name || ' ' || c.last_name as customer_name,
    c.city,
    COUNT(o.id) as order_count,
    SUM(o.total_amount) as total_spent,
    AVG(o.total_amount) as avg_order,
    MAX(o.total_amount) as max_order
FROM customers c
JOIN orders o ON c.id = o.customer_id
WHERE o.order_date >= '2023-01-01'
GROUP BY c.id, c.first_name, c.last_name, c.city
HAVING COUNT(o.id) >= 2 
   AND SUM(o.total_amount) > 50000
   AND AVG(o.total_amount) > 20000
ORDER BY total_spent DESC;

-- Товары с высокими продажами
SELECT 
    p.name as product_name,
    c.name as category_name,
    COUNT(o.id) as times_ordered,
    SUM(o.quantity) as total_quantity,
    SUM(o.total_amount) as total_revenue
FROM products p
JOIN orders o ON p.id = o.product_id
JOIN categories c ON p.category_id = c.id
GROUP BY p.id, p.name, c.name
HAVING COUNT(o.id) >= 2 OR SUM(o.total_amount) > 100000
ORDER BY total_revenue DESC;
```

## Комплексные задачи

**Задача 13:** Создайте полный CRUD цикл для нового товара

```sql
-- 1. Добавление
INSERT INTO products (name, price, category_id, stock_quantity) 
VALUES ('Новый товар', 2500.00, 1, 10);

-- 2. Чтение
SELECT * FROM products WHERE name = 'Новый товар';

-- 3. Обновление
UPDATE products 
SET price = 2750.00, stock_quantity = 15 
WHERE name = 'Новый товар';

-- 4. Удаление
DELETE FROM products WHERE name = 'Новый товар';
```

**Задача 14:** Найдите клиентов из Москвы, обновите их статус и экспортируйте список

```sql
-- 1. Добавим поле статуса
ALTER TABLE customers ADD COLUMN status VARCHAR(20) DEFAULT 'active';

-- 2. Найдем клиентов из Москвы
SELECT * FROM customers WHERE city = 'Москва';

-- 3. Обновим их статус
UPDATE customers SET status = 'vip' WHERE city = 'Москва';

-- 4. Экспортируем
\copy (SELECT first_name, last_name, email, status FROM customers WHERE status = 'vip') TO 'vip_customers.csv' CSV HEADER;
```
