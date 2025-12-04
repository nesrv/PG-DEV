# Урок по оператору `NATURAL JOIN` в PostgreSQL (без REFERENCES)

## Что такое `NATURAL JOIN`?

**NATURAL JOIN** — это тип соединения таблиц, который автоматически соединяет таблицы по столбцам с одинаковыми именами. PostgreSQL сам определяет, какие столбцы использовать для соединения.

## Синтаксис

```sql
SELECT *
FROM table1
NATURAL JOIN table2;
```

## Практический пример

### Создадим тестовые таблицы без REFERENCES

```sql
-- Таблица отделов
CREATE TABLE departments (
    department_id INTEGER,
    department_name VARCHAR(100),
    location VARCHAR(100)
);

-- Таблица сотрудников
CREATE TABLE employees (
    employee_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    department_id INTEGER, -- общий столбец с departments
    salary DECIMAL(10, 2)
);

-- Таблица проектов
CREATE TABLE projects (
    project_id INTEGER,
    project_name VARCHAR(100),
    department_id INTEGER, -- общий столбец с departments
    budget DECIMAL(10, 2)
);

-- Вставим данные в departments
INSERT INTO departments (department_id, department_name, location) VALUES
(1, 'ИТ', 'Москва'),
(2, 'Кадры', 'Санкт-Петербург'),
(3, 'Продажи', 'Екатеринбург'),
(4, 'Маркетинг', 'Новосибирск');
(5, 'Пряники', 'Тула');

-- Вставим данные в employees
INSERT INTO employees (employee_id, first_name, last_name, department_id, salary) VALUES
(1, 'Иван', 'Петров', 1, 80000),
(2, 'Мария', 'Сидорова', 1, 75000),
(3, 'Алексей', 'Козлов', 2, 65000),
(4, 'Елена', 'Морозова', 3, 70000),
(5, 'Дмитрий', 'Волков', NULL, 60000),
(6, 'Анна', 'Новикова', 4, 68000);

-- Вставим данные в projects
INSERT INTO projects (project_id, project_name, department_id, budget) VALUES
(101, 'Редизайн сайта', 1, 500000),
(102, 'Система найма', 2, 300000),
(103, 'Обучение продажам', 3, 400000),
(104, 'Рекламная кампания', 4, 600000),
(105, 'Мобильное приложение', 1, 800000);
(106, 'Миграция на постгрес', NULL, 800000);
```

## Примеры NATURAL JOIN

### Пример 1: Простое соединение employees и departments

```sql
SELECT *
FROM employees
NATURAL JOIN departments;
```

**Результат:** Соединится по столбцу `department_id`
| employee_id | first_name | last_name | department_id | salary | department_name | location |
|-------------|------------|-----------|---------------|--------|-----------------|----------|
| 1 | Иван | Петров | 1 | 80000.00 | ИТ | Москва |
| 2 | Мария | Сидорова | 1 | 75000.00 | ИТ | Москва |
| 3 | Алексей | Козлов | 2 | 65000.00 | Кадры | Санкт-Петербург |
| 4 | Елена | Морозова | 3 | 70000.00 | Продажи | Екатеринбург |
| 6 | Анна | Новикова | 4 | 68000.00 | Маркетинг | Новосибирск |

### Пример 2: Выбор конкретных столбцов

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    d.department_name,
    e.salary,
    d.location
FROM employees e
NATURAL JOIN departments d;
```

### Пример 3: NATURAL JOIN с projects

```sql
SELECT 
    p.project_id,
    p.project_name,
    d.department_name,
    p.budget,
    d.location
FROM projects p
NATURAL JOIN departments d;
```

## Разные типы NATURAL JOIN

### 1. NATURAL INNER JOIN (по умолчанию)

```sql
-- Только сотрудники с отделами
SELECT *
FROM employees
NATURAL INNER JOIN departments;
```

### 2. NATURAL LEFT JOIN

```sql
-- Все сотрудники, даже без отделов
SELECT *
FROM employees
NATURAL LEFT JOIN departments;
```

**Результат:** Дмитрий Волков будет с NULL в столбцах department

### 3. NATURAL RIGHT JOIN

```sql
-- Все отделы, даже без сотрудников
SELECT *
FROM employees
NATURAL RIGHT JOIN departments;
```

### 4. NATURAL FULL OUTER JOIN

```sql
-- Все сотрудники и все отделы
SELECT *
FROM employees
NATURAL FULL OUTER JOIN departments;
```

## Множественные NATURAL JOIN

### Соединение трех таблиц

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    d.department_name,
    p.project_name,
    p.budget
FROM employees e
NATURAL JOIN departments d
NATURAL JOIN projects p;
```

**Примечание:** Будет соединение по всем общим столбцам!

## Опасности NATURAL JOIN

### Пример с случайным совпадением имен

```sql
-- Создадим таблицу с совпадающим именем столбца
CREATE TABLE employee_contacts (
    employee_id INTEGER,
    phone VARCHAR(20),
    email VARCHAR(100),
    salary DECIMAL(10, 2) -- Случайное совпадение с employees.salary!
);

INSERT INTO employee_contacts VALUES
(1, '+7-900-123-4567', 'ivan@email.com', 80000),
(2, '+7-900-234-5678', 'maria@email.com', 75000),
(3, '+7-900-345-6789', 'alexey@email.com', 65000);

-- Опасный запрос! Соединится по employee_id И salary
SELECT *
FROM employees
NATURAL JOIN employee_contacts;
```

## Практические задания

### Задание 1: Найти всех сотрудников IT отдела

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    e.salary
FROM employees e
NATURAL JOIN departments d
WHERE d.department_name = 'ИТ';
```

### Задание 2: Найти проекты с бюджетом больше 10000 и их отделы

```sql
SELECT 
    p.project_name,
    d.department_name,
    p.budget,
    d.location
FROM projects p
NATURAL JOIN departments d
WHERE p.budget > 10000;
```

### Задание 3: Найти сотрудников и их проекты

```sql
SELECT 
    e.first_name,
    e.last_name,
    d.department_name,
    p.project_name
FROM employees e
NATURAL JOIN departments d
NATURAL JOIN projects p;
```

## Как проверить, по каким столбцам произойдет соединение?

```sql
-- Для двух таблиц
SELECT 'employees' as table_name, column_name 
FROM information_schema.columns 
WHERE table_name = 'employees' 
UNION ALL
SELECT 'departments' as table_name, column_name 
FROM information_schema.columns 
WHERE table_name = 'departments'
ORDER BY column_name, table_name;
```

## Альтернатива с явным JOIN (рекомендуется)

```sql
-- Вместо NATURAL JOIN лучше использовать явное указание столбцов
SELECT *
FROM employees e
INNER JOIN departments d ON e.department_id = d.department_id;

SELECT *
FROM employees e
LEFT JOIN departments d ON e.department_id = d.department_id;
```

## Примеры с HAVING

### Группировка и фильтрация групп с NATURAL JOIN

```sql
-- Отделы со средней зарплатой больше 70000
SELECT 
    d.department_name,
    COUNT(e.employee_id) as employee_count,
    AVG(e.salary) as avg_salary,
    SUM(e.salary) as total_salary
FROM employees e
NATURAL JOIN departments d
GROUP BY d.department_id, d.department_name
HAVING AVG(e.salary) > 70000;
```

```sql
-- Отделы с количеством сотрудников больше 1
SELECT 
    d.department_name,
    d.location,
    COUNT(e.employee_id) as employee_count,
    MIN(e.salary) as min_salary,
    MAX(e.salary) as max_salary
FROM employees e
NATURAL JOIN departments d
GROUP BY d.department_id, d.department_name, d.location
HAVING COUNT(e.employee_id) > 1;
```

```sql
-- Отделы с общим фондом зарплат больше 100000
SELECT 
    d.department_name,
    COUNT(e.employee_id) as employee_count,
    SUM(e.salary) as total_payroll
FROM employees e
NATURAL JOIN departments d
GROUP BY d.department_id, d.department_name
HAVING SUM(e.salary) > 100000
ORDER BY total_payroll DESC;
```

### Анализ проектов с HAVING

```sql
-- Отделы с общим бюджетом проектов больше 500000
SELECT 
    d.department_name,
    COUNT(p.project_id) as project_count,
    SUM(p.budget) as total_budget,
    AVG(p.budget) as avg_budget
FROM projects p
NATURAL JOIN departments d
GROUP BY d.department_id, d.department_name
HAVING SUM(p.budget) > 500000;
```

```sql
-- Отделы с количеством проектов больше 1 И средним бюджетом больше 400000
SELECT 
    d.department_name,
    d.location,
    COUNT(p.project_id) as project_count,
    AVG(p.budget) as avg_budget,
    SUM(p.budget) as total_budget
FROM projects p
NATURAL JOIN departments d
GROUP BY d.department_id, d.department_name, d.location
HAVING COUNT(p.project_id) > 1 AND AVG(p.budget) > 400000;
```

### Комплексный анализ с тремя таблицами

```sql
-- Отделы с сотрудниками и проектами: анализ эффективности
SELECT 
    d.department_name,
    COUNT(DISTINCT e.employee_id) as employee_count,
    COUNT(DISTINCT p.project_id) as project_count,
    AVG(e.salary) as avg_salary,
    SUM(p.budget) as total_budget,
    SUM(p.budget) / COUNT(DISTINCT e.employee_id) as budget_per_employee
FROM departments d
NATURAL LEFT JOIN employees e
NATURAL LEFT JOIN projects p
GROUP BY d.department_id, d.department_name
HAVING COUNT(DISTINCT e.employee_id) > 0 
   AND COUNT(DISTINCT p.project_id) > 0
   AND SUM(p.budget) / COUNT(DISTINCT e.employee_id) > 200000
ORDER BY budget_per_employee DESC;
```

### Практические задания с HAVING

**Задание 4:** Найдите отделы, где разница между максимальной и минимальной зарплатой больше 10000

```sql
SELECT 
    d.department_name,
    COUNT(e.employee_id) as employee_count,
    MIN(e.salary) as min_salary,
    MAX(e.salary) as max_salary,
    MAX(e.salary) - MIN(e.salary) as salary_range
FROM employees e
NATURAL JOIN departments d
GROUP BY d.department_id, d.department_name
HAVING MAX(e.salary) - MIN(e.salary) > 10000;
```

**Задание 5:** Найдите города с общим бюджетом проектов больше 600000

```sql
SELECT 
    d.location,
    COUNT(p.project_id) as project_count,
    SUM(p.budget) as total_budget,
    AVG(p.budget) as avg_budget
FROM projects p
NATURAL JOIN departments d
GROUP BY d.location
HAVING SUM(p.budget) > 600000
ORDER BY total_budget DESC;
```

**Задание 6:** Найдите отделы, где средняя зарплата больше среднего бюджета проекта

```sql
SELECT 
    d.department_name,
    AVG(e.salary) as avg_salary,
    AVG(p.budget) as avg_project_budget,
    COUNT(e.employee_id) as employee_count,
    COUNT(p.project_id) as project_count
FROM departments d
NATURAL LEFT JOIN employees e
NATURAL LEFT JOIN projects p
GROUP BY d.department_id, d.department_name
HAVING AVG(e.salary) > AVG(p.budget)
   AND COUNT(e.employee_id) > 0
   AND COUNT(p.project_id) > 0;
```

## Выводы

**NATURAL JOIN полезен для:**
- Быстрых запросов и анализа данных
- Когда вы точно знаете структуру таблиц
- Для временных запросов
- Группировки и агрегации с HAVING

**Не используйте NATURAL JOIN для:**
- Когда возможны изменения в структуре таблиц
- Когда есть риск случайных совпадений имен столбцов

