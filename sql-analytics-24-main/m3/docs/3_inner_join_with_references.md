# Урок по оператору `JOIN` в PostgreSQL (с REFERENCES)

## Что такое `JOIN`?

**JOIN** — это операция соединения таблиц по указанным условиям. В отличие от NATURAL JOIN, мы явно указываем, по каким столбцам происходит соединение.

## Синтаксис

```sql
SELECT *
FROM table1
JOIN table2 ON table1.column = table2.column;
```

## Практический пример

### Добавим связи к существующим таблицам

```sql
-- Добавим первичные ключи
ALTER TABLE departments ADD PRIMARY KEY (department_id);
ALTER TABLE employees ADD PRIMARY KEY (employee_id);
ALTER TABLE projects ADD PRIMARY KEY (project_id);

-- Добавим внешние ключи
ALTER TABLE employees 
ADD CONSTRAINT fk_employees_department 
FOREIGN KEY (department_id) REFERENCES departments(department_id);

ALTER TABLE projects 
ADD CONSTRAINT fk_projects_department 
FOREIGN KEY (department_id) REFERENCES departments(department_id);
```

## Примеры JOIN

### Пример 1: Простое соединение employees и departments

```sql
SELECT *
FROM employees e
JOIN departments d ON e.department_id = d.department_id;
```

**Результат:** Соединится по столбцу `department_id`
| employee_id | first_name | last_name | department_id | salary | department_id | department_name | location |
|-------------|------------|-----------|---------------|--------|---------------|-----------------|----------|
| 1 | Иван | Петров | 1 | 80000.00 | 1 | ИТ | Москва |
| 2 | Мария | Сидорова | 1 | 75000.00 | 1 | ИТ | Москва |
| 3 | Алексей | Козлов | 2 | 65000.00 | 2 | Кадры | Санкт-Петербург |
| 4 | Елена | Морозова | 3 | 70000.00 | 3 | Продажи | Екатеринбург |
| 6 | Анна | Новикова | 4 | 68000.00 | 4 | Маркетинг | Новосибирск |

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
JOIN departments d ON e.department_id = d.department_id;
```

### Пример 3: JOIN с projects

```sql
SELECT 
    p.project_id,
    p.project_name,
    d.department_name,
    p.budget,
    d.location
FROM projects p
JOIN departments d ON p.department_id = d.department_id;
```

## Разные типы JOIN

### 1. INNER JOIN (по умолчанию)

```sql
-- Только сотрудники с отделами
SELECT *
FROM employees e
INNER JOIN departments d ON e.department_id = d.department_id;
```

### 2. LEFT JOIN

```sql
-- Все сотрудники, даже без отделов
SELECT *
FROM employees e
LEFT JOIN departments d ON e.department_id = d.department_id;
```

**Результат:** Дмитрий Волков будет с NULL в столбцах department

### 3. RIGHT JOIN

```sql
-- Все отделы, даже без сотрудников
SELECT *
FROM employees e
RIGHT JOIN departments d ON e.department_id = d.department_id;
```

### 4. FULL OUTER JOIN

```sql
-- Все сотрудники и все отделы
SELECT *
FROM employees e
FULL OUTER JOIN departments d ON e.department_id = d.department_id;
```

## Множественные JOIN

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
JOIN departments d ON e.department_id = d.department_id
JOIN projects p ON d.department_id = p.department_id;
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
JOIN departments d ON e.department_id = d.department_id
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
JOIN departments d ON p.department_id = d.department_id
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
JOIN departments d ON e.department_id = d.department_id
JOIN projects p ON d.department_id = p.department_id;
```

## Примеры с HAVING

### Группировка и фильтрация групп с JOIN

```sql
-- Отделы со средней зарплатой больше 70000
SELECT 
    d.department_name,
    COUNT(e.employee_id) as employee_count,
    AVG(e.salary) as avg_salary,
    SUM(e.salary) as total_salary
FROM employees e
JOIN departments d ON e.department_id = d.department_id
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
JOIN departments d ON e.department_id = d.department_id
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
JOIN departments d ON e.department_id = d.department_id
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
JOIN departments d ON p.department_id = d.department_id
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
JOIN departments d ON p.department_id = d.department_id
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
LEFT JOIN employees e ON d.department_id = e.department_id
LEFT JOIN projects p ON d.department_id = p.department_id
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
JOIN departments d ON e.department_id = d.department_id
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
JOIN departments d ON p.department_id = d.department_id
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
LEFT JOIN employees e ON d.department_id = e.department_id
LEFT JOIN projects p ON d.department_id = p.department_id
GROUP BY d.department_id, d.department_name
HAVING AVG(e.salary) > AVG(p.budget)
   AND COUNT(e.employee_id) > 0
   AND COUNT(p.project_id) > 0;
```

## Выводы

**JOIN с явным указанием условий полезен для:**
- Точного контроля над соединениями таблиц
- Безопасности от случайных изменений структуры
- Читаемости и понимания кода
- Группировки и агрегации с HAVING

**Преимущества REFERENCES:**
- Обеспечивает целостность данных
- Предотвращает вставку несуществующих ссылок
- Автоматически создает индексы для внешних ключей
- Улучшает производительность JOIN операций