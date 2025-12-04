# `crosstab()` 

преобразует строки в столбцы (пивотирует таблицу).



## Задача

В таблице `sales` хранится информация о продажах товаров по месяцам:

| product  | month | sales\_amount |
| -------- | ----- | ------------- |
| ProductA | Jan   | 100           |
| ProductA | Feb   | 120           |
| ProductB | Jan   | 80            |
| ProductB | Feb   | 90            |


```sql

CREATE TABLE sales1 (
    product TEXT NOT NULL,
    month TEXT NOT NULL,
    sales_amount INT NOT NULL
);

INSERT INTO sales1 (product, month, sales_amount) VALUES
('ProductA', 'Jan', 100),
('ProductA', 'Feb', 120),
('ProductB', 'Jan', 80),
('ProductB', 'Feb', 90);


table sales1;

```

**Требуется вывести таблицу, где будет одна строка на продукт, а столбцы — продажи по месяцам:**

| product  | Jan | Feb |
| -------- | --- | --- |
| ProductA | 100 | 120 |
| ProductB | 80  | 90  |

---

## Решение с использованием `crosstab()`

1. Убедитесь, что установлен модуль `tablefunc`:

```sql
CREATE EXTENSION IF NOT EXISTS tablefunc;
```

2. Запрос с `crosstab()`:

```sql
SELECT *
FROM crosstab(
    'SELECT product, month, sales_amount FROM sales1 ORDER BY 1,2',
    $$VALUES ('Jan'), ('Feb')$$
) AS ct(product TEXT, Jan INT, Feb INT);
```

---

## Пояснения:

* Первый параметр — SQL-запрос, возвращающий три колонки: строка (product), ключ (month) и значение (sales\_amount).
* Второй параметр — список всех значений, которые будут превращены в столбцы (месяцы).
* `AS ct(...)` — описание итоговой структуры таблицы.

