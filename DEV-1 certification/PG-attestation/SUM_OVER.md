


## SUM OVER (PARTITION BY ... ORDER BY ...) 


Вот пример использования агрегатной функции `SUM(*)` с оконной функцией `OVER (PARTITION BY ... ORDER BY ...)` в PostgreSQL — это называется **накапливаемая сумма (running total)** по группам.

---

### Исходная таблица: `sales`

```sql
CREATE TABLE sales (
    id SERIAL PRIMARY KEY,
    employee TEXT,
    region TEXT,
    sale_date DATE,
    amount NUMERIC
);
```

Данные:

```sql
INSERT INTO sales (employee, region, sale_date, amount) VALUES
('Alice', 'East', '2024-01-01', 100),
('Alice', 'East', '2024-01-02', 200),
('Alice', 'East', '2024-01-03', 150),
('Bob', 'West',  '2024-01-01', 300),
('Bob', 'West',  '2024-01-03', 100),
('Bob', 'West',  '2024-01-04', 200);
```

---

### Задача:

Получить **накопленную сумму `amount` для каждого сотрудника**, отсортированную по дате продажи.

---

### Запрос с оконной функцией:

```sql
SELECT
    employee,
    region,
    sale_date,
    amount,
    SUM(amount) OVER (PARTITION BY employee ORDER BY sale_date) AS running_total
FROM sales
ORDER BY employee, sale_date;
```

---

### Результат:

| employee | region | sale\_date | amount | running\_total |
| -------- | ------ | ---------- | ------ | -------------- |
| Alice    | East   | 2024-01-01 | 100    | 100            |
| Alice    | East   | 2024-01-02 | 200    | 300            |
| Alice    | East   | 2024-01-03 | 150    | 450            |
| Bob      | West   | 2024-01-01 | 300    | 300            |
| Bob      | West   | 2024-01-03 | 100    | 400            |
| Bob      | West   | 2024-01-04 | 200    | 600            |

---

🔹 **`PARTITION BY employee`** — делает накопление отдельно для каждого сотрудника.
🔹 **`ORDER BY sale_date`** — определяет порядок накопления.
🔹 **`SUM(...) OVER (...)`** — превращает агрегатную функцию в оконную, возвращая результат построчно.

```sql
SELECT
    employee,
    sale_date,
    amount,
    AVG(amount) OVER (PARTITION BY employee ORDER BY sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_avg,
    MIN(amount) OVER (PARTITION BY employee ORDER BY sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_min
FROM sales
ORDER BY employee, sale_date;
```


Отлично! PostgreSQL поддерживает **расширенные опции `GROUP BY`**: `GROUPING SETS`, `ROLLUP` и `CUBE`. Эти возможности позволяют делать **многомерную агрегацию** (как в OLAP) и заменяют множество объединений (`UNION ALL`) в одном запросе.

---
