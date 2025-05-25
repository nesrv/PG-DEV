# `GROUPING SETS`, `CUBE` и `ROLLUP` 
это продвинутые способы группировки для отчетов с разными уровнями детализации.


```sql
CREATE TABLE sales (
    seller TEXT NOT NULL,
    product TEXT NOT NULL,
    amount NUMERIC NOT NULL
);

INSERT INTO sales (seller, product, amount) VALUES
('Alice', 'Widget', 100),
('Alice', 'Gadget', 150),
('Bob', 'Widget', 200),
('Bob', 'Gadget', 50),
('Carol', 'Widget', 300),
('Carol', 'Gadget', 75);
```


### 1. Задача:

Посчитать сумму продаж (`amount`) по `seller` и `product` с отдельными итогами по каждому продавцу, каждому продукту и общей итоговой суммой.

---

### Решение с `GROUPING SETS`:

```sql
SELECT
    seller,
    product,
    SUM(amount) AS total_amount
FROM sales
GROUP BY ...
ORDER BY ...;
```

---

### 2. Задача:

Посчитать сумму продаж по комбинациям `seller` и `product` и получить все возможные агрегаты — все варианты группировок: по каждому продавцу, по каждому продукту, по продавцу и продукту вместе, а также общий итог.

---

### Решение с `CUBE`:

```sql
SELECT
    seller,
    product,
    SUM(amount) AS total_amount
FROM sales
GROUP BY CUBE ...
ORDER BY ...;
```

---

### 3. Задача:

Посчитать сумму продаж по `seller` и `product` с агрегатами, которые включают промежуточные итоги по продавцу и общий итог, то есть получить детализацию по каждому продукту в рамках продавца, а также итог по продавцу и общий итог.

---

### Решение с `ROLLUP`:

```sql
SELECT
    seller,
    product,
    SUM(amount) AS total_amount
FROM sales
GROUP BY ROLLUP ...
ORDER BY ...;
```

---

# Пояснения

* `GROUPING SETS` позволяет явно указать нужные группы.
* `CUBE` создает все возможные комбинации группировок для указанных столбцов.
* `ROLLUP` создаёт иерархию агрегатов, группируя по столбцам последовательно.


