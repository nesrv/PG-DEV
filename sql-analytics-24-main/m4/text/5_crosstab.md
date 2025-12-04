# Кросс-таблицы в PostgreSQL: Преобразование строк в столбцы

## Введение

**Кросс-таблица (crosstab)** — это способ преобразования данных из строк в столбцы. Это полезно для создания отчетов, где нужно показать данные в табличном виде с категориями по осям.

## Подготовка данных

Создадим таблицу продаж по месяцам и продуктам:

```sql
CREATE TABLE monthly_sales (
    product TEXT NOT NULL,
    month TEXT NOT NULL,
    sales_amount NUMERIC NOT NULL,
    region TEXT NOT NULL
);

INSERT INTO monthly_sales (product, month, sales_amount, region) VALUES
('Ноутбуки', 'Январь', 150000, 'Москва'),
('Ноутбуки', 'Февраль', 180000, 'Москва'),
('Ноутбуки', 'Март', 200000, 'Москва'),
('Телефоны', 'Январь', 120000, 'Москва'),
('Телефоны', 'Февраль', 140000, 'Москва'),
('Телефоны', 'Март', 160000, 'Москва'),
('Планшеты', 'Январь', 80000, 'Москва'),
('Планшеты', 'Февраль', 90000, 'Москва'),
('Планшеты', 'Март', 110000, 'Москва'),
('Ноутбуки', 'Январь', 100000, 'СПб'),
('Ноутбуки', 'Февраль', 120000, 'СПб'),
('Телефоны', 'Январь', 80000, 'СПб'),
('Телефоны', 'Февраль', 95000, 'СПб');
```

**Исходные данные:**
```
product   | month   | sales_amount | region
----------|---------|--------------|--------
Ноутбуки  | Январь  | 150000      | Москва
Ноутбуки  | Февраль | 180000      | Москва
Телефоны  | Январь  | 120000      | Москва
...
```

**Цель:** Преобразовать в формат:
```
product   | Январь | Февраль | Март
----------|--------|---------|------
Ноутбуки  | 150000 | 180000  | 200000
Телефоны  | 120000 | 140000  | 160000
Планшеты  | 80000  | 90000   | 110000
```

---

## Метод 1: Использование CASE WHEN (стандартный SQL)

### Базовый пример
```sql
SELECT 
    product,
    SUM(CASE WHEN month = 'Январь' THEN sales_amount ELSE 0 END) AS "Январь",
    SUM(CASE WHEN month = 'Февраль' THEN sales_amount ELSE 0 END) AS "Февраль",
    SUM(CASE WHEN month = 'Март' THEN sales_amount ELSE 0 END) AS "Март"
FROM monthly_sales
WHERE region = 'Москва'
GROUP BY product
ORDER BY product;
```

### Расширенный пример с итогами
```sql
SELECT 
    product,
    SUM(CASE WHEN month = 'Январь' THEN sales_amount ELSE 0 END) AS "Январь",
    SUM(CASE WHEN month = 'Февраль' THEN sales_amount ELSE 0 END) AS "Февраль",
    SUM(CASE WHEN month = 'Март' THEN sales_amount ELSE 0 END) AS "Март",
    SUM(sales_amount) AS "Итого",
    ROUND(AVG(sales_amount), 0) AS "Среднее"
FROM monthly_sales
WHERE region = 'Москва'
GROUP BY product
ORDER BY "Итого" DESC;
```

---

## Метод 2: Функция crosstab() (PostgreSQL)

### Установка расширения
```sql
CREATE EXTENSION IF NOT EXISTS tablefunc;
```

### Базовый crosstab
```sql
SELECT *
FROM crosstab(
    'SELECT product, month, sales_amount 
     FROM monthly_sales 
     WHERE region = ''Москва''
     ORDER BY 1, 2',
    $$VALUES ('Январь'), ('Февраль'), ('Март')$$
) AS ct(
    product TEXT, 
    "Январь" NUMERIC, 
    "Февраль" NUMERIC, 
    "Март" NUMERIC
);
```

### Crosstab с автоматическим определением категорий
```sql
-- Сначала получаем список месяцев
SELECT DISTINCT month FROM monthly_sales ORDER BY month;

-- Затем используем crosstab
SELECT *
FROM crosstab(
    'SELECT product, month, sales_amount 
     FROM monthly_sales 
     WHERE region = ''Москва''
     ORDER BY 1, 2'
) AS ct(
    product TEXT, 
    "Январь" NUMERIC, 
    "Февраль" NUMERIC, 
    "Март" NUMERIC
);
```

---

## Продвинутые техники

### 1. Многоуровневая группировка
```sql
SELECT 
    region,
    product,
    SUM(CASE WHEN month = 'Январь' THEN sales_amount ELSE 0 END) AS "Январь",
    SUM(CASE WHEN month = 'Февраль' THEN sales_amount ELSE 0 END) AS "Февраль",
    SUM(CASE WHEN month = 'Март' THEN sales_amount ELSE 0 END) AS "Март"
FROM monthly_sales
GROUP BY region, product
ORDER BY region, product;
```

### 2. Процентное соотношение
```sql
WITH totals AS (
    SELECT 
        product,
        SUM(CASE WHEN month = 'Январь' THEN sales_amount ELSE 0 END) AS jan,
        SUM(CASE WHEN month = 'Февраль' THEN sales_amount ELSE 0 END) AS feb,
        SUM(CASE WHEN month = 'Март' THEN sales_amount ELSE 0 END) AS mar,
        SUM(sales_amount) AS total
    FROM monthly_sales
    WHERE region = 'Москва'
    GROUP BY product
)
SELECT 
    product,
    jan AS "Январь",
    feb AS "Февраль", 
    mar AS "Март",
    ROUND(jan * 100.0 / total, 1) AS "% Январь",
    ROUND(feb * 100.0 / total, 1) AS "% Февраль",
    ROUND(mar * 100.0 / total, 1) AS "% Март"
FROM totals
ORDER BY total DESC;
```

### 3. Динамическая кросс-таблица
```sql
-- Функция для создания динамической кросс-таблицы
CREATE OR REPLACE FUNCTION dynamic_crosstab(
    table_name TEXT,
    row_column TEXT,
    category_column TEXT,
    value_column TEXT,
    where_clause TEXT DEFAULT ''
)
RETURNS TABLE(result TEXT) AS $$
DECLARE
    query TEXT;
    categories TEXT;
BEGIN
    -- Получаем список категорий
    EXECUTE format(
        'SELECT string_agg(DISTINCT %I, '','') FROM %I %s',
        category_column, table_name, where_clause
    ) INTO categories;
    
    -- Строим запрос
    query := format(
        'SELECT %I, %s FROM %I %s GROUP BY %I ORDER BY %I',
        row_column,
        (SELECT string_agg(
            format('SUM(CASE WHEN %I = ''%s'' THEN %I ELSE 0 END) AS "%s"',
                   category_column, cat, value_column, cat),
            ', '
        ) FROM unnest(string_to_array(categories, ',')) AS cat),
        table_name,
        where_clause,
        row_column,
        row_column
    );
    
    RETURN QUERY EXECUTE query;
END;
$$ LANGUAGE plpgsql;
```

---

## Практические примеры

### Пример 1: Отчет по регионам
```sql
SELECT 
    region,
    SUM(CASE WHEN product = 'Ноутбуки' THEN sales_amount ELSE 0 END) AS "Ноутбуки",
    SUM(CASE WHEN product = 'Телефоны' THEN sales_amount ELSE 0 END) AS "Телефоны",
    SUM(CASE WHEN product = 'Планшеты' THEN sales_amount ELSE 0 END) AS "Планшеты",
    SUM(sales_amount) AS "Итого"
FROM monthly_sales
GROUP BY region
ORDER BY "Итого" DESC;
```

### Пример 2: Сравнение периодов
```sql
WITH current_period AS (
    SELECT product, SUM(sales_amount) as current_sales
    FROM monthly_sales 
    WHERE month IN ('Февраль', 'Март')
    GROUP BY product
),
previous_period AS (
    SELECT product, SUM(sales_amount) as previous_sales
    FROM monthly_sales 
    WHERE month = 'Январь'
    GROUP BY product
)
SELECT 
    c.product,
    p.previous_sales AS "Январь",
    c.current_sales AS "Февраль-Март",
    c.current_sales - p.previous_sales AS "Изменение",
    ROUND((c.current_sales - p.previous_sales) * 100.0 / p.previous_sales, 1) AS "% изменения"
FROM current_period c
JOIN previous_period p ON c.product = p.product
ORDER BY "% изменения" DESC;
```

### Пример 3: Топ-N анализ
```sql
WITH ranked_products AS (
    SELECT 
        product,
        month,
        sales_amount,
        RANK() OVER (PARTITION BY month ORDER BY sales_amount DESC) as rank
    FROM monthly_sales
    WHERE region = 'Москва'
)
SELECT 
    product,
    SUM(CASE WHEN month = 'Январь' AND rank <= 2 THEN sales_amount END) AS "Топ-2 Январь",
    SUM(CASE WHEN month = 'Февраль' AND rank <= 2 THEN sales_amount END) AS "Топ-2 Февраль",
    SUM(CASE WHEN month = 'Март' AND rank <= 2 THEN sales_amount END) AS "Топ-2 Март"
FROM ranked_products
WHERE rank <= 2
GROUP BY product
ORDER BY product;
```

---

## Сравнение методов

| Метод | Преимущества | Недостатки |
|-------|-------------|------------|
| **CASE WHEN** | Стандартный SQL, работает везде | Нужно знать категории заранее |
| **crosstab()** | Более гибкий, автоматическое определение | Только PostgreSQL, сложнее |
| **Динамический** | Полностью автоматический | Сложная реализация |

---

## Рекомендации

1. **Для простых случаев** — используйте CASE WHEN
2. **Для сложных отчетов** — crosstab()
3. **Всегда добавляйте итоги** для лучшего понимания
4. **Используйте осмысленные названия** столбцов
5. **Сортируйте результаты** по важности

---

## Заключение

Кросс-таблицы — мощный инструмент для создания аналитических отчетов. Выбор метода зависит от сложности задачи и требований к гибкости. CASE WHEN подходит для большинства случаев, а crosstab() — для более сложных сценариев.