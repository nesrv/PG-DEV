# Урок: Функция LAG() в PostgreSQL

## Подготовка данных

Создадим таблицу продаж для демонстрации:

```sql
CREATE TABLE sales (
    id SERIAL PRIMARY KEY,
    seller TEXT,
    sale_date DATE,
    amount NUMERIC
);

INSERT INTO sales (seller, sale_date, amount) VALUES
('Дмитрий', '2024-01-01', 100),
('Дмитрий', '2024-01-05', 200),
('Дмитрий', '2024-01-10', 300),
('Катерина', '2024-01-02', 400),
('Катерина', '2024-01-07', 100),
('Катерина', '2024-01-08', 600),
('Олег', '2024-01-03', 300),
('Олег', '2024-01-10', 300),
('Олег', '2024-01-12', 300);
```

## Пример 1: LAG() без ORDER BY

```sql
SELECT seller, amount, LAG(amount) OVER (PARTITION BY seller)
FROM sales;
```

**Проблема:** Без `ORDER BY` порядок строк непредсказуем. PostgreSQL может вернуть строки в любом порядке, поэтому результат будет случайным.

**Результат может быть:**

```
seller    | amount | lag
----------|--------|----
Дмитрий   | 200    | NULL
Дмитрий   | 100    | 200
Дмитрий   | 300    | 100
```

**Вывод:** Всегда используйте `ORDER BY` с оконными функциями!

## Пример 2: LAG() с ORDER BY

```sql
SELECT seller, amount, LAG(amount) OVER (PARTITION BY seller ORDER BY sale_date)
FROM sales;
```

**Объяснение:**

- `PARTITION BY seller` — группируем по продавцам
- `ORDER BY sale_date` — сортируем по дате внутри каждой группы
- `LAG(amount)` — берем значение из предыдущей строки

**Результат:**

```
seller    | amount | lag
----------|--------|----
Дмитрий   | 100    | NULL  ← первая строка
Дмитрий   | 200    | 100   ← предыдущее значение
Дмитрий   | 300    | 200
Катерина  | 400    | NULL  ← первая строка для Катерины
Катерина  | 100    | 400
Катерина  | 600    | 100
Олег      | 300    | NULL  ← первая строка для Олега
Олег      | 300    | 300
Олег      | 300    | 300
```

## Пример 3: LAG() с параметрами

```sql
SELECT seller, amount, LAG(amount, 1, 0) OVER (PARTITION BY seller ORDER BY sale_date)
FROM sales;
```

**Параметры функции LAG():**

1. **`amount`** — столбец для получения значения
2. **`1`** — смещение (на сколько строк назад)
3. **`0`** — значение по умолчанию вместо NULL

**Результат:**

```
seller    | amount | lag
----------|--------|----
Дмитрий   | 100    | 0     ← вместо NULL возвращает 0
Дмитрий   | 200    | 100
Дмитрий   | 300    | 200
Катерина  | 400    | 0     ← вместо NULL возвращает 0
Катерина  | 100    | 400
Катерина  | 600    | 100
```

## Пример 4: Полный запрос с алиасами

```sql
SELECT
    seller,
    sale_date,
    amount,
    LAG(amount) OVER (PARTITION BY seller ORDER BY sale_date) AS previous_amount
FROM sales;
```

**Результат:**

```
seller    | sale_date  | amount | previous_amount
----------|------------|--------|----------------
Дмитрий   | 2024-01-01 | 100    | NULL
Дмитрий   | 2024-01-05 | 200    | 100
Дмитрий   | 2024-01-10 | 300    | 200
Катерина  | 2024-01-02 | 400    | NULL
Катерина  | 2024-01-07 | 100    | 400
Катерина  | 2024-01-08 | 600    | 100
Олег      | 2024-01-03 | 300    | NULL
Олег      | 2024-01-10 | 300    | 300
Олег      | 2024-01-12 | 300    | 300
```

## Практическое применение

### Вычисление изменения продаж

```sql
SELECT
    seller,
    sale_date,
    amount,
    amount - LAG(amount) OVER (PARTITION BY seller ORDER BY sale_date) AS change
FROM sales;


-- Полный анализ динамики продаж с вычислением разницы
SELECT
    seller,
    sale_date,
    amount,
    LAG(amount) OVER (PARTITION BY seller ORDER BY sale_date) AS previous_amount,
    amount - LAG(amount) OVER (PARTITION BY seller ORDER BY sale_date) AS difference,
    ROUND((amount - LAG(amount) OVER (PARTITION BY seller ORDER BY sale_date)) / 
          LAG(amount) OVER (PARTITION BY seller ORDER BY sale_date) * 100, 2) AS growth_percent
FROM sales;

```

### Конструкция WINDOW

позволяет определить окно один раз и использовать его многократно.

Как работает:

```sql
WINDOW w AS (PARTITION BY seller ORDER BY sale_date) -- определяем окно с именем w
LAG(amount) OVER w -- используем это окно в функции
```

Преимущества:

Избегаем повторения длинного определения окна

Код становится читаемее при использовании одного окна в нескольких функциях

Пример с несколькими функциями:

```sql
SELECT seller, amount, 
       LAG(amount) OVER w AS prev_amount,
       LEAD(amount) OVER w AS next_amount,
       ROW_NUMBER() OVER w AS row_num
FROM sales
WINDOW w AS (PARTITION BY seller ORDER BY sale_date);
```

Без WINDOW пришлось бы три раза писать `(PARTITION BY seller ORDER BY sale_date)`.

## Практическое использование:

* Анализ динамики продаж по каждому продавцу
* Выявление трендов и аномалий
* Сравнение текущих показателей с предыдущими
* Расчет процентного роста/падения продаж

## Заключение

Функция LAG() - мощный инструмент для анализа временных рядов и последовательных данных. Ключевые моменты для запоминания:

Всегда используйте ORDER BY для предсказуемых результатов
PARTITION BY создает отдельные окна для групп
Указывайте значение по умолчанию для обработки NULL значений
Функция полезна для расчета разниц, роста и других метрик

## Ключевые моменты

1. **Всегда используйте ORDER BY** — без него результат непредсказуем
2. **PARTITION BY** — разделяет данные на группы
3. **Смещение** — второй параметр определяет, на сколько строк назад смотреть
4. **Значение по умолчанию** — третий параметр заменяет NULL
5. **NULL в первой строке** — LAG() возвращает NULL для первой строки каждой группы

## Альтернативы LAG()

### Использование WINDOW

```sql
SELECT seller, amount, LAG(amount) OVER w AS prev_amount
FROM sales
WINDOW w AS (PARTITION BY seller ORDER BY sale_date);
```

### Смещение на 2 строки назад

```sql
SELECT seller, amount, LAG(amount, 2) OVER (PARTITION BY seller ORDER BY sale_date)
FROM sales;
```
