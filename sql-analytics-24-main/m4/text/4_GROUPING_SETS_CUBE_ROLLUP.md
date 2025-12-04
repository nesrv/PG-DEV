# Многоуровневая группировка: GROUPING SETS, CUBE и ROLLUP

## Введение

**Многоуровневая группировка** позволяет создавать отчеты с разными уровнями детализации в одном запросе. Это мощный инструмент для аналитики и создания сводных отчетов.

## Простые примеры для понимания

Начнем с базовой таблицы:

```sql
CREATE TABLE simple_sales (
    seller TEXT,
    product TEXT,
    amount NUMERIC
);

INSERT INTO simple_sales VALUES
('Олег', 'Телефон', 1000),
('Олег', 'Планшет', 800),
('Катерина', 'Телефон', 1200),
('Катерина', 'Планшет', 900);
```

### Обычная группировка (для сравнения)

```sql
-- Только по продавцам
SELECT seller, SUM(amount) FROM simple_sales GROUP BY seller;
-- Результат: Олег=1800, Катерина=2100

-- Только по продуктам  
SELECT product, SUM(amount) FROM simple_sales GROUP BY product;
-- Результат: Телефон=2200, Планшет=1700
```

### GROUPING SETS — выбираем что нужно

```sql
-- 1

SELECT seller, SUM(amount)
FROM simple_sales
GROUP BY GROUPING SETS (
    seller    -- Итоги по продавцам
);

--2 
SELECT seller, product, SUM(amount)
FROM simple_sales
GROUP BY GROUPING SETS (
    seller,    -- Итоги по продавцам
	product
);


SELECT 
    seller, 
    product, 
    SUM(amount) as total
FROM simple_sales
GROUP BY GROUPING SETS (
    (seller),     -- Итоги по продавцам
    (product),    -- Итоги по продуктам  
    ()           -- Общий итог
)
	ORDER by 1,2;
```

**Результат:**

```
seller   | product | total
---------|---------|------
Олег     | NULL    | 1800
Катерина | NULL    | 2100
NULL     | Телефон | 2200
NULL     | Планшет | 1700
NULL     | NULL    | 3900
```

### CUBE — все комбинации

```sql
SELECT 
    seller, 
    product, 
    SUM(amount) as total
FROM simple_sales
GROUP BY CUBE (seller, product);
```

**Результат включает ВСЕ возможные группировки:**

- По продавцу и продукту
- Только по продавцу
- Только по продукту
- Общий итог

### ROLLUP — иерархия

```sql
SELECT 
    seller, 
    product, 
    SUM(amount) as total
FROM simple_sales
GROUP BY ROLLUP (seller, product);
```

**Результат показывает иерархию:**

1. Детализация: продавец + продукт
2. Итог по продавцу
3. Общий итог

---

## Подготовка данных для сложных примеров

Теперь создадим более сложную таблицу:

```sql
CREATE TABLE sales_report (
    seller TEXT NOT NULL,
    product_category TEXT NOT NULL,
    region TEXT NOT NULL,
    quarter TEXT NOT NULL,
    amount NUMERIC NOT NULL
);

INSERT INTO sales_report (seller, product_category, region, quarter, amount) VALUES
-- Олег
('Олег', 'Электроника', 'Москва', 'Q1', 150000),
('Олег', 'Электроника', 'Москва', 'Q2', 180000),
('Олег', 'Одежда', 'Москва', 'Q1', 80000),
('Олег', 'Одежда', 'СПб', 'Q1', 70000),
-- Катерина
('Катерина', 'Электроника', 'СПб', 'Q1', 200000),
('Катерина', 'Электроника', 'СПб', 'Q2', 220000),
('Катерина', 'Книги', 'Москва', 'Q1', 50000),
('Катерина', 'Книги', 'СПб', 'Q2', 60000),
-- Стас
('Стас', 'Одежда', 'Москва', 'Q1', 120000),
('Стас', 'Одежда', 'Москва', 'Q2', 140000),
('Стас', 'Электроника', 'СПб', 'Q1', 100000),
('Стас', 'Книги', 'Москва', 'Q2', 40000);
```

---

## GROUPING SETS — Точечная группировка

**GROUPING SETS** позволяет явно указать, какие именно группировки нужны.

### Базовый пример

```sql
SELECT
    seller,
    product_category,
    SUM(amount) AS total_sales
FROM sales_report
GROUP BY GROUPING SETS (
    (seller, product_category),  -- По продавцу и категории
    (seller),                    -- Только по продавцу
    (product_category),          -- Только по категории
    ()                          -- Общий итог
)
ORDER BY seller NULLS LAST, product_category NULLS LAST;
```

**Результат:**

```
seller   | product_category | total_sales
---------|------------------|------------
Катерина | Книги           | 110000
Катерина | Электроника     | 420000
Олег     | Одежда          | 150000
Олег     | Электроника     | 330000
Стас     | Книги           | 40000
Стас     | Одежда          | 260000
Стас     | Электроника     | 100000
Катерина | NULL            | 530000      ← Итог по Катерине
Олег     | NULL            | 480000      ← Итог по Олегу
Стас     | NULL            | 400000      ← Итог по Стасу
NULL     | Книги           | 150000      ← Итог по книгам
NULL     | Одежда          | 410000      ← Итог по одежде
NULL     | Электроника     | 850000      ← Итог по электронике
NULL     | NULL            | 1410000     ← Общий итог
```

### Расширенный пример с регионами

```sql
SELECT
    seller,
    region,
    product_category,
    SUM(amount) AS total_sales,
    COUNT(*) AS transaction_count
FROM sales_report
GROUP BY GROUPING SETS (
    (seller, region, product_category),  -- Полная детализация
    (seller, region),                    -- По продавцу и региону
    (seller),                           -- Только по продавцу
    (region),                           -- Только по региону
    ()                                  -- Общий итог
)
ORDER BY seller NULLS LAST, region NULLS LAST, product_category NULLS LAST;
```

---

## CUBE — Все возможные комбинации

**CUBE** создает все возможные комбинации группировок для указанных столбцов.

### Формула CUBE

Для n столбцов CUBE создает 2^n группировок.

**CUBE(A, B)** эквивалентно:

```sql
GROUPING SETS (
    (A, B),    -- Обе колонки
    (A),       -- Только A
    (B),       -- Только B
    ()         -- Без группировки (общий итог)
)
```

### Пример с двумя измерениями

```sql
SELECT
    seller,
    product_category,
    SUM(amount) AS total_sales,
    ROUND(AVG(amount), 0) AS avg_sales
FROM sales_report
GROUP BY CUBE (seller, product_category)
ORDER BY seller NULLS LAST, product_category NULLS LAST;
```

### Пример с тремя измерениями

```sql
SELECT
    seller,
    region,
    quarter,
    SUM(amount) AS total_sales,
    -- Используем GROUPING для определения уровня агрегации
    CASE 
        WHEN GROUPING(seller) = 0 AND GROUPING(region) = 0 AND GROUPING(quarter) = 0 
        THEN 'Детализация'
        WHEN GROUPING(seller) = 0 AND GROUPING(region) = 0 
        THEN 'По продавцу и региону'
        WHEN GROUPING(seller) = 0 
        THEN 'По продавцу'
        WHEN GROUPING(region) = 0 
        THEN 'По региону'
        WHEN GROUPING(quarter) = 0 
        THEN 'По кварталу'
        ELSE 'Общий итог'
    END AS aggregation_level
FROM sales_report
GROUP BY CUBE (seller, region, quarter)
ORDER BY seller NULLS LAST, region NULLS LAST, quarter NULLS LAST;
```

---

## ROLLUP — Иерархическая группировка

**ROLLUP** создает иерархию агрегатов, группируя по столбцам последовательно.

### Принцип работы ROLLUP

**ROLLUP(A, B, C)** эквивалентно:

```sql
GROUPING SETS (
    (A, B, C),    -- Полная группировка
    (A, B),       -- Без последнего уровня
    (A),          -- Только первый уровень
    ()            -- Общий итог
)
```

### Пример: Иерархия продавец → категория

```sql
SELECT
    seller,
    product_category,
    SUM(amount) AS total_sales,
    COUNT(*) AS transactions,
    -- Определяем уровень иерархии
    CASE 
        WHEN GROUPING(seller) = 0 AND GROUPING(product_category) = 0 
        THEN 'Продавец + Категория'
        WHEN GROUPING(seller) = 0 
        THEN 'Итог по продавцу'
        ELSE 'Общий итог'
    END AS hierarchy_level
FROM sales_report
GROUP BY ROLLUP (seller, product_category)
ORDER BY seller NULLS LAST, product_category NULLS LAST;
```

### Пример: Трехуровневая иерархия

```sql
SELECT
    seller,
    region,
    product_category,
    SUM(amount) AS total_sales,
    ROUND(AVG(amount), 0) AS avg_transaction,
    -- Показываем уровень детализации
    CONCAT(
        CASE WHEN GROUPING(seller) = 0 THEN seller ELSE 'ВСЕ' END,
        ' → ',
        CASE WHEN GROUPING(region) = 0 THEN region ELSE 'ВСЕ' END,
        ' → ',
        CASE WHEN GROUPING(product_category) = 0 THEN product_category ELSE 'ВСЕ' END
    ) AS hierarchy_path
FROM sales_report
GROUP BY ROLLUP (seller, region, product_category)
ORDER BY seller NULLS LAST, region NULLS LAST, product_category NULLS LAST;
```

---

## Функция GROUPING() — Определение уровня агрегации

**GROUPING()** возвращает 1, если столбец участвует в агрегации (NULL), и 0, если нет.

### Практическое использование

```sql
SELECT
    CASE WHEN GROUPING(seller) = 0 THEN seller ELSE 'ИТОГО' END AS seller_display,
    CASE WHEN GROUPING(product_category) = 0 THEN product_category ELSE 'ВСЕ КАТЕГОРИИ' END AS category_display,
    SUM(amount) AS total_sales,
    -- Создаем читаемые метки
    CASE 
        WHEN GROUPING(seller) = 1 AND GROUPING(product_category) = 1 THEN 'ОБЩИЙ ИТОГ'
        WHEN GROUPING(seller) = 1 THEN 'ИТОГ ПО КАТЕГОРИИ'
        WHEN GROUPING(product_category) = 1 THEN 'ИТОГ ПО ПРОДАВЦУ'
        ELSE 'ДЕТАЛИЗАЦИЯ'
    END AS report_level
FROM sales_report
GROUP BY ROLLUP (seller, product_category)
ORDER BY GROUPING(seller), seller, GROUPING(product_category), product_category;
```

---

## Практические кейсы

### Кейс 1: Финансовый отчет по кварталам

```sql
SELECT
    COALESCE(seller, 'ИТОГО') AS seller_name,
    COALESCE(quarter, 'ВСЕ КВАРТАЛЫ') AS quarter_name,
    SUM(amount) AS revenue,
    COUNT(*) AS deals_count,
    ROUND(SUM(amount) / COUNT(*), 0) AS avg_deal_size,
    -- Процент от общего объема
    ROUND(
        SUM(amount) * 100.0 / SUM(SUM(amount)) OVER (), 
        1
    ) AS percent_of_total
FROM sales_report
GROUP BY ROLLUP (seller, quarter)
ORDER BY seller NULLS LAST, quarter NULLS LAST;
```

### Кейс 2: Анализ по регионам и категориям

```sql
WITH regional_analysis AS (
    SELECT
        region,
        product_category,
        SUM(amount) AS total_sales,
        COUNT(DISTINCT seller) AS sellers_count,
        GROUPING(region) AS region_grouping,
        GROUPING(product_category) AS category_grouping
    FROM sales_report
    GROUP BY CUBE (region, product_category)
)
SELECT
    CASE 
        WHEN region_grouping = 0 THEN region 
        ELSE 'ВСЕ РЕГИОНЫ' 
    END AS region_display,
    CASE 
        WHEN category_grouping = 0 THEN product_category 
        ELSE 'ВСЕ КАТЕГОРИИ' 
    END AS category_display,
    total_sales,
    sellers_count,
    CASE 
        WHEN region_grouping = 0 AND category_grouping = 0 THEN 'Детальный анализ'
        WHEN region_grouping = 0 THEN 'Итог по региону'
        WHEN category_grouping = 0 THEN 'Итог по категории'
        ELSE 'Общий итог'
    END AS analysis_type
FROM regional_analysis
ORDER BY region_grouping, region, category_grouping, product_category;
```

### Кейс 3: Сравнительный анализ продавцов

```sql
SELECT
    seller,
    product_category,
    SUM(amount) AS sales,
    -- Ранг продавца в категории
    CASE WHEN GROUPING(product_category) = 0 THEN
        RANK() OVER (PARTITION BY product_category ORDER BY SUM(amount) DESC)
    END AS rank_in_category,
    -- Доля в категории
    CASE WHEN GROUPING(product_category) = 0 THEN
        ROUND(
            SUM(amount) * 100.0 / 
            SUM(SUM(amount)) OVER (PARTITION BY product_category), 
            1
        )
    END AS category_share_percent
FROM sales_report
GROUP BY GROUPING SETS (
    (seller, product_category),
    (seller),
    (product_category),
    ()
)
ORDER BY 
    GROUPING(seller), 
    GROUPING(product_category), 
    seller, 
    product_category;
```

---

## Оптимизация и лучшие практики

### 1. Использование индексов

```sql
-- Создаем составные индексы для группировок
CREATE INDEX idx_sales_seller_category ON sales_report (seller, product_category);
CREATE INDEX idx_sales_region_quarter ON sales_report (region, quarter);
```

### 2. Материализованные представления для сложных отчетов

```sql
CREATE MATERIALIZED VIEW sales_cube_mv AS
SELECT
    seller,
    product_category,
    region,
    quarter,
    SUM(amount) AS total_sales,
    COUNT(*) AS transaction_count,
    AVG(amount) AS avg_transaction,
    GROUPING(seller) AS seller_grouping,
    GROUPING(product_category) AS category_grouping,
    GROUPING(region) AS region_grouping,
    GROUPING(quarter) AS quarter_grouping
FROM sales_report
GROUP BY CUBE (seller, product_category, region, quarter);

-- Обновление представления
REFRESH MATERIALIZED VIEW sales_cube_mv;
```

### 3. Функция для автоматического создания отчетов

```sql
CREATE OR REPLACE FUNCTION generate_sales_report(
    grouping_type TEXT DEFAULT 'ROLLUP',
    columns_list TEXT[] DEFAULT ARRAY['seller', 'product_category']
)
RETURNS TABLE(
    dimension1 TEXT,
    dimension2 TEXT,
    total_sales NUMERIC,
    report_level TEXT
) AS $$
DECLARE
    query TEXT;
BEGIN
    query := format(
        'SELECT 
            COALESCE(%I::TEXT, ''ИТОГО'') as dimension1,
            COALESCE(%I::TEXT, ''ВСЕ'') as dimension2,
            SUM(amount) as total_sales,
            CASE 
                WHEN GROUPING(%I) = 1 AND GROUPING(%I) = 1 THEN ''ОБЩИЙ ИТОГ''
                WHEN GROUPING(%I) = 1 THEN ''ИТОГ ПО ВТОРОМУ''
                WHEN GROUPING(%I) = 1 THEN ''ИТОГ ПО ПЕРВОМУ''
                ELSE ''ДЕТАЛИЗАЦИЯ''
            END as report_level
         FROM sales_report 
         GROUP BY %s (%I, %I)
         ORDER BY GROUPING(%I), %I, GROUPING(%I), %I',
        columns_list[1], columns_list[2],
        columns_list[1], columns_list[2],
        columns_list[2], columns_list[1],
        grouping_type, columns_list[1], columns_list[2],
        columns_list[1], columns_list[1], columns_list[2], columns_list[2]
    );
  
    RETURN QUERY EXECUTE query;
END;
$$ LANGUAGE plpgsql;

-- Использование функции
SELECT * FROM generate_sales_report('CUBE', ARRAY['seller', 'region']);
```

---

## Сравнение методов

| Метод              | Количество группировок | Использование                                      | Пример                                             |
| ----------------------- | ------------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------- |
| **GROUPING SETS** | Точно указанные               | Когда нужны конкретные комбинации | Итоги по продавцам + общий итог |
| **CUBE**          | 2^n (все комбинации)           | Полный анализ всех измерений           | Анализ продаж по всем срезам     |
| **ROLLUP**        | n+1 (иерархия)                      | Иерархические отчеты                         | Компания → Регион → Продавец     |

---

## Заключение

Многоуровневая группировка — мощный инструмент для создания аналитических отчетов:

- **GROUPING SETS** — для точечного контроля группировок
- **CUBE** — для полного анализа всех комбинаций
- **ROLLUP** — для иерархических структур
- **GROUPING()** — для определения уровня агрегации

Выбор метода зависит от типа отчета и требуемого уровня детализации.
