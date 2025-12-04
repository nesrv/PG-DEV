# LAST_VALUE() — Финальная точка

⚠️ **Ловушка новичка:** По умолчанию окно идет от начала до текущей строки!

## Что происходит по умолчанию

PostgreSQL использует **неявные границы окна**:
- `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`
- Это означает: от первой строки группы до текущей строки

## Демонстрация проблемы

**Данные:**
```
Дмитрий: 100 (01.01) → 200 (05.01) → 300 (10.01)
```

**Неправильно (возвращает текущее значение):**
```sql
SELECT
    seller,
    sale_date,
    amount,
    LAST_VALUE(amount) OVER (PARTITION BY seller ORDER BY sale_date) AS wrong_last
FROM sales;
```

**Результат:**
```
seller   | sale_date  | amount | wrong_last
---------|------------|--------|------------
Дмитрий  | 2024-01-01 | 100    | 100        ← окно: [100]
Дмитрий  | 2024-01-05 | 200    | 200        ← окно: [100, 200]  
Дмитрий  | 2024-01-10 | 300    | 300        ← окно: [100, 200, 300]
```

## Правильное решение

**Указываем границы окна явно:**
```sql
SELECT
    seller,
    sale_date,
    amount,
    LAST_VALUE(amount) OVER (
        PARTITION BY seller ORDER BY sale_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS correct_last
FROM sales;
```

**Результат:**
```
seller   | sale_date  | amount | correct_last
---------|------------|--------|-------------
Дмитрий  | 2024-01-01 | 100    | 300         ← окно: [100, 200, 300]
Дмитрий  | 2024-01-05 | 200    | 300         ← окно: [100, 200, 300]
Дмитрий  | 2024-01-10 | 300    | 300         ← окно: [100, 200, 300]
```

## Объяснение границ окна

- **`UNBOUNDED PRECEDING`** — от самой первой строки группы
- **`UNBOUNDED FOLLOWING`** — до самой последней строки группы
- **`CURRENT ROW`** — текущая строка (по умолчанию)

## Альтернативные варианты границ

```sql
-- Последние 3 строки
ROWS BETWEEN 2 PRECEDING AND CURRENT ROW

-- Текущая и следующие 2 строки  
ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING

-- Все строки в группе
ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
```

## Практический пример с проверкой

```sql
SELECT
    seller,
    sale_date,
    amount,
    LAST_VALUE(amount) OVER w AS final_amount,
    CASE 
        WHEN amount = LAST_VALUE(amount) OVER w 
        THEN 'Финальная сделка'
        ELSE 'Промежуточная'
    END AS deal_status
FROM sales
WINDOW w AS (
    PARTITION BY seller ORDER BY sale_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
ORDER BY seller, sale_date;
```

## Ключевое правило

**Всегда явно указывайте границы окна для `LAST_VALUE()`**, иначе получите текущее значение вместо последнего!