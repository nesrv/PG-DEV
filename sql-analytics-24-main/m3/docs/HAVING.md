# HAVING в PostgreSQL

## Что такое HAVING

**HAVING** - условие для фильтрации групп после GROUP BY. Работает с агрегатными функциями.

**Разница между WHERE и HAVING:**
- `WHERE` - фильтрует строки ДО группировки
- `HAVING` - фильтрует группы ПОСЛЕ группировки

## Подготовка данных

```sql
-- Создаем тестовые таблицы
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(50),
    salary DECIMAL(10,2),
    hire_date DATE
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER,
    amount DECIMAL(10,2),
    order_date DATE
);

-- Заполняем данными
INSERT INTO employees (name, department, salary, hire_date) VALUES
('Иван Петров', 'IT', 80000, '2020-01-15'),
('Мария Сидорова', 'IT', 75000, '2021-03-10'),
('Алексей Козлов', 'IT', 90000, '2019-06-20'),
('Елена Морозова', 'HR', 60000, '2020-08-05'),
('Дмитрий Волков', 'HR', 65000, '2021-01-12'),
('Анна Новикова', 'Sales', 70000, '2020-04-18'),
('Петр Смирнов', 'Sales', 72000, '2021-07-25'),
('Ольга Кузнецова', 'Sales', 68000, '2020-11-30');

INSERT INTO orders (customer_id, amount, order_date) VALUES
(1, 1500.00, '2023-01-15'),
(1, 2300.00, '2023-02-20'),
(2, 800.00, '2023-01-25'),
(2, 1200.00, '2023-03-10'),
(2, 950.00, '2023-04-05'),
(3, 3200.00, '2023-02-14'),
(4, 450.00, '2023-01-30'),
(5, 1800.00, '2023-03-22'),
(5, 2100.00, '2023-04-18');
```

## Основы HAVING

### Простой пример

```sql
-- Отделы со средней зарплатой больше 70000
SELECT 
    department,
    AVG(salary) as avg_salary,
    COUNT(*) as employee_count
FROM employees
GROUP BY department
HAVING AVG(salary) > 70000;
```

### Сравнение WHERE и HAVING

```sql
-- WHERE - фильтрует строки ДО группировки
SELECT 
    department,
    AVG(salary) as avg_salary
FROM employees
WHERE salary > 70000  -- сначала отбираем сотрудников с зарплатой > 70000
GROUP BY department;

-- HAVING - фильтрует группы ПОСЛЕ группировки
SELECT 
    department,
    AVG(salary) as avg_salary
FROM employees
GROUP BY department
HAVING AVG(salary) > 70000;  -- отбираем отделы со средней зарплатой > 70000
```

## Примеры с разными агрегатными функциями

### COUNT с HAVING

```sql
-- Отделы с количеством сотрудников больше 2
SELECT 
    department,
    COUNT(*) as employee_count
FROM employees
GROUP BY department
HAVING COUNT(*) > 2;

-- Клиенты с количеством заказов больше 2
SELECT 
    customer_id,
    COUNT(*) as order_count
FROM orders
GROUP BY customer_id
HAVING COUNT(*) > 2;
```

### SUM с HAVING

```sql
-- Клиенты с общей суммой заказов больше 3000
SELECT 
    customer_id,
    SUM(amount) as total_amount,
    COUNT(*) as order_count
FROM orders
GROUP BY customer_id
HAVING SUM(amount) > 3000;

-- Отделы с общим фондом зарплат больше 200000
SELECT 
    department,
    SUM(salary) as total_salary,
    COUNT(*) as employee_count
FROM employees
GROUP BY department
HAVING SUM(salary) > 200000;
```

### MIN/MAX с HAVING

```sql
-- Отделы с максимальной зарплатой больше 80000
SELECT 
    department,
    MAX(salary) as max_salary,
    MIN(salary) as min_salary
FROM employees
GROUP BY department
HAVING MAX(salary) > 80000;

-- Клиенты с максимальным заказом больше 2000
SELECT 
    customer_id,
    MAX(amount) as max_order,
    COUNT(*) as order_count
FROM orders
GROUP BY customer_id
HAVING MAX(amount) > 2000;
```

## Сложные условия в HAVING

### Несколько условий

```sql
-- Отделы с количеством > 2 И средней зарплатой > 70000
SELECT 
    department,
    COUNT(*) as employee_count,
    AVG(salary) as avg_salary
FROM employees
GROUP BY department
HAVING COUNT(*) > 2 AND AVG(salary) > 70000;

-- Клиенты с суммой заказов от 2000 до 4000
SELECT 
    customer_id,
    SUM(amount) as total_amount,
    COUNT(*) as order_count
FROM orders
GROUP BY customer_id
HAVING SUM(amount) BETWEEN 2000 AND 4000;
```

### HAVING с OR

```sql
-- Отделы с количеством > 3 ИЛИ средней зарплатой > 80000
SELECT 
    department,
    COUNT(*) as employee_count,
    AVG(salary) as avg_salary
FROM employees
GROUP BY department
HAVING COUNT(*) > 3 OR AVG(salary) > 80000;
```

## HAVING с WHERE

```sql
-- Сначала WHERE, потом GROUP BY, потом HAVING
SELECT 
    department,
    AVG(salary) as avg_salary,
    COUNT(*) as employee_count
FROM employees
WHERE hire_date >= '2020-01-01'  -- сначала фильтруем по дате найма
GROUP BY department
HAVING AVG(salary) > 70000;      -- потом фильтруем группы по средней зарплате

-- Заказы 2023 года, клиенты с суммой > 2000
SELECT 
    customer_id,
    SUM(amount) as total_amount,
    COUNT(*) as order_count
FROM orders
WHERE EXTRACT(YEAR FROM order_date) = 2023
GROUP BY customer_id
HAVING SUM(amount) > 2000;
```

## Практические задачи

### Задача 1: Анализ продаж
```sql
-- Найти клиентов со средним чеком больше 1500
SELECT 
    customer_id,
    AVG(amount) as avg_order,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
GROUP BY customer_id
HAVING AVG(amount) > 1500;
```

### Задача 2: HR аналитика
```sql
-- Отделы с разбросом зарплат больше 15000
SELECT 
    department,
    MAX(salary) - MIN(salary) as salary_range,
    AVG(salary) as avg_salary,
    COUNT(*) as employee_count
FROM employees
GROUP BY department
HAVING MAX(salary) - MIN(salary) > 15000;
```

### Задача 3: Временной анализ
```sql
-- Месяцы с количеством заказов больше 2
SELECT 
    EXTRACT(YEAR FROM order_date) as year,
    EXTRACT(MONTH FROM order_date) as month,
    COUNT(*) as order_count,
    SUM(amount) as total_amount
FROM orders
GROUP BY EXTRACT(YEAR FROM order_date), EXTRACT(MONTH FROM order_date)
HAVING COUNT(*) > 2
ORDER BY year, month;
```

## HAVING с подзапросами

```sql
-- Отделы со средней зарплатой выше общей средней
SELECT 
    department,
    AVG(salary) as avg_salary,
    COUNT(*) as employee_count
FROM employees
GROUP BY department
HAVING AVG(salary) > (SELECT AVG(salary) FROM employees);

-- Клиенты с суммой заказов выше средней суммы по всем клиентам
SELECT 
    customer_id,
    SUM(amount) as total_amount
FROM orders
GROUP BY customer_id
HAVING SUM(amount) > (
    SELECT AVG(customer_total) 
    FROM (
        SELECT SUM(amount) as customer_total 
        FROM orders 
        GROUP BY customer_id
    ) as customer_totals
);
```

## Распространенные ошибки

### ❌ Неправильно - использование не агрегатной функции в HAVING
```sql
-- ОШИБКА: нельзя использовать обычные поля в HAVING без агрегации
SELECT department, COUNT(*)
FROM employees
GROUP BY department
HAVING name = 'Иван Петров';  -- ОШИБКА!
```

### ✅ Правильно - использование WHERE для обычных полей
```sql
SELECT department, COUNT(*)
FROM employees
WHERE name = 'Иван Петров'  -- WHERE для обычных полей
GROUP BY department;
```

## Порядок выполнения SQL

```sql
SELECT department, AVG(salary)     -- 5. SELECT
FROM employees                     -- 1. FROM
WHERE hire_date >= '2020-01-01'    -- 2. WHERE
GROUP BY department                -- 3. GROUP BY
HAVING AVG(salary) > 70000         -- 4. HAVING
ORDER BY AVG(salary) DESC          -- 6. ORDER BY
LIMIT 5;                          -- 7. LIMIT
```

## Комплексный пример

```sql
-- Анализ эффективности отделов
SELECT 
    department,
    COUNT(*) as employee_count,
    AVG(salary) as avg_salary,
    MIN(salary) as min_salary,
    MAX(salary) as max_salary,
    MAX(salary) - MIN(salary) as salary_range,
    SUM(salary) as total_salary_cost
FROM employees
WHERE hire_date >= '2020-01-01'
GROUP BY department
HAVING COUNT(*) >= 2 
   AND AVG(salary) > 65000
   AND MAX(salary) - MIN(salary) < 25000
ORDER BY avg_salary DESC;
```

## Практические упражнения

**Упражнение 1:** Найдите отделы с общим фондом зарплат больше 150000

**Упражнение 2:** Найдите клиентов, у которых минимальный заказ больше 1000

**Упражнение 3:** Найдите месяцы, в которых средний чек был больше 1500

## Решения упражнений

```sql
-- Упражнение 1
SELECT 
    department,
    SUM(salary) as total_salary,
    COUNT(*) as employee_count
FROM employees
GROUP BY department
HAVING SUM(salary) > 150000;

-- Упражнение 2
SELECT 
    customer_id,
    MIN(amount) as min_order,
    COUNT(*) as order_count
FROM orders
GROUP BY customer_id
HAVING MIN(amount) > 1000;

-- Упражнение 3
SELECT 
    EXTRACT(YEAR FROM order_date) as year,
    EXTRACT(MONTH FROM order_date) as month,
    AVG(amount) as avg_amount,
    COUNT(*) as order_count
FROM orders
GROUP BY EXTRACT(YEAR FROM order_date), EXTRACT(MONTH FROM order_date)
HAVING AVG(amount) > 1500
ORDER BY year, month;
```