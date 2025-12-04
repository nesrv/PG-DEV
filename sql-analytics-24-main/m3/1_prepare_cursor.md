# Подготовленные операторы и курсоры в PostgreSQL

## Подготовленные операторы (PREPARE/EXECUTE)

### Что такое подготовленные операторы?

**Подготовленные операторы** — это механизм PostgreSQL для оптимизации повторяющихся запросов. Запрос компилируется один раз, а затем выполняется многократно с разными параметрами.

### Создание тестовых данных

```sql
-- Создадим таблицу для демонстрации
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    price DECIMAL(10,2),
    category_id INTEGER,
    stock_quantity INTEGER
);

INSERT INTO products (name, price, category_id, stock_quantity) VALUES
('Ноутбук Dell', 75000.00, 1, 15),
('iPhone 15', 89000.00, 2, 25),
('Клавиатура Logitech', 3500.00, 1, 50),
('Наушники Sony', 12000.00, 2, 30),
('Монитор Samsung', 25000.00, 1, 20),
('Мышь Razer', 4500.00, 1, 40),
('Планшет iPad', 65000.00, 2, 18),
('Веб-камера', 8000.00, 1, 35);
```

### Базовый синтаксис PREPARE

```sql
-- Подготавливаем запрос с параметром
PREPARE find_product(integer) AS
SELECT * FROM products WHERE id = $1;

-- Выполняем подготовленный запрос
EXECUTE find_product(1);
```

### Практические примеры

#### Пример 1: Поиск товаров по категории

```sql
PREPARE products_by_category(integer) AS
SELECT name, price, stock_quantity 
FROM products 
WHERE category_id = $1 
ORDER BY price DESC;

EXECUTE products_by_category(1);
EXECUTE products_by_category(2);
```

#### Пример 2: Сложный запрос с несколькими параметрами

```sql
PREPARE search_products(decimal, decimal, integer) AS
SELECT name, price, stock_quantity,
       CASE 
           WHEN stock_quantity < 20 THEN 'Мало на складе'
           WHEN stock_quantity < 30 THEN 'Средний запас'
           ELSE 'Достаточно'
       END as stock_status
FROM products 
WHERE price BETWEEN $1 AND $2 
  AND stock_quantity >= $3
ORDER BY price;

-- Найти товары от 5000 до 30000 рублей с остатком >= 20
EXECUTE search_products(5000, 30000, 20);
```

#### Пример 3: Подготовленный INSERT

```sql
PREPARE add_product(varchar, decimal, integer, integer) AS
INSERT INTO products (name, price, category_id, stock_quantity) 
VALUES ($1, $2, $3, $4) 
RETURNING id, name;

EXECUTE add_product('Принтер HP', 15000.00, 1, 12);
```

#### Пример 4: Подготовленный UPDATE

```sql
PREPARE update_stock(integer, integer) AS
UPDATE products 
SET stock_quantity = stock_quantity + $2
WHERE id = $1
RETURNING name, stock_quantity;

-- Увеличить запас товара с id=1 на 5 единиц
EXECUTE update_stock(1, 5);
```

### Управление подготовленными операторами

```sql
-- Просмотр всех подготовленных операторов
SELECT name, statement, parameter_types 
FROM pg_prepared_statements;

-- Удаление конкретного оператора
DEALLOCATE find_product;

-- Удаление всех подготовленных операторов
DEALLOCATE ALL;
```

### Преимущества подготовленных операторов

- **Производительность**: план выполнения кэшируется
- **Безопасность**: защита от SQL-инъекций
- **Удобство**: переиспользование сложных запросов
- **Экономия ресурсов**: меньше времени на парсинг

## Курсоры (CURSOR)

### Что такое курсоры?

**Курсор** — это механизм для пошагового чтения больших результирующих наборов данных. Вместо загрузки всех строк в память сразу, курсор позволяет обрабатывать данные порциями.

### Создание большой таблицы для демонстрации

```sql
-- Создадим таблицу с большим количеством данных
CREATE TABLE sales_log (
    id SERIAL PRIMARY KEY,
    sale_date DATE,
    product_id INTEGER,
    quantity INTEGER,
    amount DECIMAL(10,2),
    customer_region VARCHAR(50)
);

-- Заполним тестовыми данными
INSERT INTO sales_log (sale_date, product_id, quantity, amount, customer_region)
SELECT 
    CURRENT_DATE - (random() * 365)::integer,
    (random() * 8 + 1)::integer,
    (random() * 10 + 1)::integer,
    (random() * 50000 + 1000)::decimal(10,2),
    CASE (random() * 4)::integer
        WHEN 0 THEN 'Москва'
        WHEN 1 THEN 'СПб'
        WHEN 2 THEN 'Екатеринбург'
        ELSE 'Новосибирск'
    END
FROM generate_series(1, 10000);
```

### Базовая работа с курсорами

```sql
BEGIN;

-- Объявляем курсор
DECLARE sales_cursor CURSOR FOR
SELECT sale_date, product_id, amount, customer_region
FROM sales_log 
WHERE amount > 25000
ORDER BY sale_date DESC;

-- Получаем первую строку
FETCH sales_cursor;

-- Получаем следующие 5 строк
FETCH 5 FROM sales_cursor;

-- Получаем все оставшиеся строки
FETCH ALL FROM sales_cursor;

CLOSE sales_cursor;
COMMIT;
```

### Типы курсоров

#### 1. Обычный курсор (только вперед)

```sql
BEGIN;
DECLARE simple_cursor CURSOR FOR
SELECT * FROM products ORDER BY price;

FETCH simple_cursor;  -- Следующая строка
FETCH 3 simple_cursor;  -- Следующие 3 строки

CLOSE simple_cursor;
COMMIT;
```

#### 2. Прокручиваемый курсор (SCROLL)

```sql
BEGIN;
DECLARE scroll_cursor SCROLL CURSOR FOR
SELECT name, price FROM products ORDER BY price;

FETCH FIRST FROM scroll_cursor;     -- Первая строка
FETCH LAST FROM scroll_cursor;      -- Последняя строка
FETCH PRIOR FROM scroll_cursor;     -- Предыдущая строка
FETCH NEXT FROM scroll_cursor;      -- Следующая строка
FETCH ABSOLUTE 3 FROM scroll_cursor; -- 3-я строка от начала
FETCH RELATIVE -2 FROM scroll_cursor; -- На 2 строки назад

CLOSE scroll_cursor;
COMMIT;
```

#### 3. Курсор с параметрами

```sql
BEGIN;
DECLARE region_cursor CURSOR(region_name varchar) FOR
SELECT sale_date, amount 
FROM sales_log 
WHERE customer_region = region_name
ORDER BY amount DESC;

-- Открываем курсор с параметром
OPEN region_cursor('Москва');
FETCH 5 region_cursor;
CLOSE region_cursor;

-- Открываем с другим параметром
OPEN region_cursor('СПб');
FETCH 3 region_cursor;
CLOSE region_cursor;

COMMIT;
```

#### 4. Курсор WITH HOLD (сохраняется после COMMIT)

```sql
BEGIN;
DECLARE persistent_cursor CURSOR WITH HOLD FOR
SELECT * FROM products ORDER BY id;

FETCH 2 persistent_cursor;
COMMIT;  -- Курсор остается открытым!

FETCH 2 persistent_cursor;  -- Продолжаем работу
CLOSE persistent_cursor;
```

### Практический пример: обработка больших данных

```sql
-- Функция для пакетной обработки продаж
CREATE OR REPLACE FUNCTION process_sales_batch()
RETURNS TABLE(region varchar, total_sales decimal, avg_amount decimal) AS $$
DECLARE
    sales_cursor CURSOR FOR 
        SELECT customer_region, amount 
        FROM sales_log 
        WHERE sale_date >= CURRENT_DATE - INTERVAL '30 days'
        ORDER BY customer_region;
    
    current_region varchar := '';
    region_total decimal := 0;
    region_count integer := 0;
    rec RECORD;
BEGIN
    OPEN sales_cursor;
    
    LOOP
        FETCH sales_cursor INTO rec;
        EXIT WHEN NOT FOUND;
        
        -- Если сменился регион, выводим итоги предыдущего
        IF current_region != '' AND current_region != rec.customer_region THEN
            region := current_region;
            total_sales := region_total;
            avg_amount := region_total / region_count;
            RETURN NEXT;
            
            region_total := 0;
            region_count := 0;
        END IF;
        
        current_region := rec.customer_region;
        region_total := region_total + rec.amount;
        region_count := region_count + 1;
    END LOOP;
    
    -- Выводим итоги последнего региона
    IF region_count > 0 THEN
        region := current_region;
        total_sales := region_total;
        avg_amount := region_total / region_count;
        RETURN NEXT;
    END IF;
    
    CLOSE sales_cursor;
END;
$$ LANGUAGE plpgsql;

-- Вызываем функцию
SELECT * FROM process_sales_batch();
```

### Мониторинг курсоров

```sql
-- Просмотр активных курсоров
SELECT 
    name,
    statement,
    is_holdable,
    is_binary,
    is_scrollable
FROM pg_cursors;
```

### Когда использовать курсоры?

**Используйте курсоры когда:**
- Обрабатываете очень большие результирующие наборы
- Нужна пошаговая обработка данных
- Ограничена память приложения
- Требуется интерактивная работа с данными

**Не используйте курсоры когда:**
- Результирующий набор небольшой (< 1000 строк)
- Можно обработать данные одним запросом
- Нужна максимальная производительность

### Оптимизация работы с курсорами

```sql
-- Настройка размера выборки для сессии
SET cursor_tuple_fraction = 0.1;  -- 10% от общего результата

-- Использование оптимального размера блока
BEGIN;
DECLARE opt_cursor CURSOR FOR
SELECT * FROM sales_log ORDER BY sale_date;

-- Читаем блоками по 1000 строк
LOOP
    FETCH 1000 opt_cursor;
    EXIT WHEN NOT FOUND;
    -- Обработка блока данных
END LOOP;

CLOSE opt_cursor;
COMMIT;
```

### Интеграция с языками программирования

#### Python (psycopg2)
```python
import psycopg2

conn = psycopg2.connect("dbname=test user=postgres")
cur = conn.cursor()

# Подготовленный оператор
cur.execute("PREPARE find_product(integer) AS SELECT * FROM products WHERE id = $1")
cur.execute("EXECUTE find_product(%s)", (1,))

# Курсор
cur.execute("DECLARE sales_cursor CURSOR FOR SELECT * FROM sales_log")
cur.execute("FETCH 100 sales_cursor")
results = cur.fetchall()
```

#### Node.js (pg)
```javascript
const { Client } = require('pg');
const client = new Client();

// Подготовленный запрос
await client.query('PREPARE find_product(integer) AS SELECT * FROM products WHERE id = $1');
const result = await client.query('EXECUTE find_product($1)', [1]);

// Курсор
await client.query('BEGIN');
await client.query('DECLARE sales_cursor CURSOR FOR SELECT * FROM sales_log');
const batch = await client.query('FETCH 100 sales_cursor');
```

## Заключение

**Подготовленные операторы** и **курсоры** — мощные инструменты PostgreSQL для:
- Оптимизации производительности
- Безопасной работы с данными
- Эффективной обработки больших объемов информации
- Контроля использования памяти

Используйте их в зависимости от специфики ваших задач и объемов обрабатываемых данных.