# Тема 5. Основы языка SQL

## История и стандарты SQL

**SQL (Structured Query Language)** - декларативный язык программирования для работы с реляционными базами данных.

### История:
- 1970 - Эдгар Кодд предложил реляционную модель
- 1974 - IBM начала проект System R
- 1982 - Первая коммерческая СУБД (Oracle V2)
- 1986 - Стандарт SQL-86 (SQL1)
- 1989 - SQL-89 (SQL1 с дополнениями)
- 1992 - SQL-92 (SQL2)
- 1999 - SQL:1999 (SQL3) - объектно-реляционные возможности
- 2003 - SQL:2003 - XML функции
- 2006 - SQL:2006 - импорт, стандартизация XML
- 2008 - SQL:2008 - команда MERGE, триггеры INSTEAD OF
- 2011 - SQL:2011 - временные данные
- 2016 - SQL:2016 - поддержка JSON

## Классификация команд SQL

### DDL (Data Definition Language) - Язык определения данных
Команды для создания и изменения структуры БД:
- `CREATE` - создание объектов
- `ALTER` - изменение объектов  
- `DROP` - удаление объектов
- `TRUNCATE` - очистка таблицы

### DML (Data Manipulation Language) - Язык манипулирования данными
Команды для работы с данными:
- `SELECT` - выборка данных
- `INSERT` - вставка данных
- `UPDATE` - обновление данных
- `DELETE` - удаление данных

### DCL (Data Control Language) - Язык управления данными
Команды для управления правами доступа:
- `GRANT` - предоставление прав
- `REVOKE` - отзыв прав

### TCL (Transaction Control Language) - Язык управления транзакциями
Команды для управления транзакциями:
- `BEGIN` - начало транзакции
- `COMMIT` - подтверждение транзакции
- `ROLLBACK` - откат транзакции
- `SAVEPOINT` - точка сохранения

## Синтаксис SQL

### Основные правила:
- Команды не чувствительны к регистру
- Строки заключаются в одинарные кавычки
- Команды заканчиваются точкой с запятой
- Комментарии: `--` или `/* */`

### Идентификаторы:
- Имена таблиц, столбцов, функций
- Начинаются с буквы или подчеркивания
- Могут содержать буквы, цифры, подчеркивания
- Максимум 63 символа в PostgreSQL

## Типы данных PostgreSQL

### Числовые типы:
```sql
SMALLINT        -- 2 байта, -32768 до 32767
INTEGER (INT)   -- 4 байта, -2147483648 до 2147483647
BIGINT          -- 8 байт
DECIMAL(p,s)    -- точное число с p цифрами, s после запятой
NUMERIC(p,s)    -- то же что DECIMAL
REAL            -- 4 байта, 6 знаков точности
DOUBLE PRECISION -- 8 байт, 15 знаков точности
SERIAL          -- автоинкремент INTEGER
BIGSERIAL       -- автоинкремент BIGINT
```

### Символьные типы:
```sql
CHAR(n)         -- строка фиксированной длины
VARCHAR(n)      -- строка переменной длины до n символов
TEXT            -- строка неограниченной длины
```

### Дата и время:
```sql
DATE            -- дата (год, месяц, день)
TIME            -- время (час, минута, секунда)
TIMESTAMP       -- дата и время
TIMESTAMPTZ     -- дата и время с часовым поясом
INTERVAL        -- интервал времени
```

### Логический тип:
```sql
BOOLEAN         -- TRUE, FALSE, NULL
```

### Другие типы:
```sql
UUID            -- универсальный уникальный идентификатор
JSON            -- JSON данные
JSONB           -- бинарный JSON
ARRAY           -- массив
```

## Практические примеры

### 1. Создание таблицы:
```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    category_id INTEGER,
    in_stock BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 2. Вставка данных:
```sql
INSERT INTO products (name, description, price, category_id)
VALUES 
('Ноутбук ASUS', 'Игровой ноутбук 15.6"', 75000.00, 1),
('Мышь Logitech', 'Беспроводная мышь', 2500.00, 1),
('Клавиатура', 'Механическая клавиатура', 8000.00, 1);
```

### 3. Простые SELECT запросы:
```sql
-- Выбрать все записи
SELECT * FROM products;

-- Выбрать определенные столбцы
SELECT name, price FROM products;

-- Выбрать с условием
SELECT name, price 
FROM products 
WHERE price > 5000;

-- Выбрать с сортировкой
SELECT name, price 
FROM products 
ORDER BY price DESC;

-- Выбрать с ограничением
SELECT name, price 
FROM products 
ORDER BY price DESC 
LIMIT 2;
```

### 4. Обновление данных:
```sql
-- Обновить цену товара
UPDATE products 
SET price = 70000.00 
WHERE name = 'Ноутбук ASUS';

-- Обновить несколько полей
UPDATE products 
SET price = price * 1.1, 
    description = description || ' (обновлено)'
WHERE category_id = 1;
```

### 5. Удаление данных:
```sql
-- Удалить конкретный товар
DELETE FROM products 
WHERE name = 'Мышь Logitech';

-- Удалить товары дороже определенной суммы
DELETE FROM products 
WHERE price > 50000;
```

## Практическое задание

### Создайте базу данных "Интернет-магазин":

1. **Создайте таблицы:**
```sql
-- Категории товаров
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description TEXT
);

-- Товары
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    in_stock BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Клиенты
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    registration_date DATE DEFAULT CURRENT_DATE
);
```

2. **Заполните таблицы данными:**
```sql
-- Категории
INSERT INTO categories (name, description) VALUES
('Электроника', 'Компьютеры, телефоны, планшеты'),
('Одежда', 'Мужская и женская одежда'),
('Книги', 'Художественная и техническая литература');

-- Товары (добавьте 10 товаров)
-- Клиенты (добавьте 5 клиентов)
```

3. **Выполните запросы:**
```sql
-- Все товары с названиями категорий
-- Товары дороже 1000 рублей
-- Клиенты, зарегистрированные в этом месяце
-- Количество товаров в каждой категории
```

## Домашнее задание

1. Изучите документацию PostgreSQL по типам данных
2. Создайте схему БД для системы управления курсами
3. Напишите 10 различных SELECT запросов
4. Подготовьте вопросы по материалу занятия