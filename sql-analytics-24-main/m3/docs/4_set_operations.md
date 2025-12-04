# Операции с множествами в PostgreSQL

## Что такое операции с множествами?

**Операции с множествами** позволяют объединять, находить различия и пересечения между результатами нескольких SELECT запросов.

## Тестовые данные

```sql
-- Таблица сотрудников ИТ отдела
CREATE TABLE it_employees (
    employee_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    skill VARCHAR(50)
);

-- Таблица сотрудников отдела маркетинга
CREATE TABLE marketing_employees (
    employee_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    skill VARCHAR(50)
);

INSERT INTO it_employees VALUES
(1, 'Иван', 'Петров', 'Python'),
(2, 'Мария', 'Сидорова', 'Java'),
(3, 'Алексей', 'Козлов', 'SQL'),
(4, 'Елена', 'Морозова', 'Python');

INSERT INTO marketing_employees VALUES
(3, 'Алексей', 'Козлов', 'SQL'),
(5, 'Дмитрий', 'Волков', 'Analytics'),
(6, 'Анна', 'Новикова', 'Design'),
(7, 'Петр', 'Иванов', 'SMM');
```

## 1. UNION - Объединение множеств

**UNION** объединяет результаты двух запросов, **исключая дубликаты**.

```sql
-- Все сотрудники из обоих отделов (без дубликатов)
SELECT first_name, last_name FROM it_employees
UNION
SELECT first_name, last_name FROM marketing_employees;
```

**Результат:**
| first_name | last_name |
|------------|-----------|
| Иван | Петров |
| Мария | Сидорова |
| Алексей | Козлов |
| Елена | Морозова |
| Дмитрий | Волков |
| Анна | Новикова |
| Петр | Иванов |

### UNION ALL - с дубликатами

```sql
-- Все сотрудники из обоих отделов (с дубликатами)
SELECT first_name, last_name FROM it_employees
UNION ALL
SELECT first_name, last_name FROM marketing_employees;
```

**Результат:** Алексей Козлов появится дважды.

### Практический пример UNION

```sql
-- Все навыки в компании
SELECT skill, 'ИТ' as department FROM it_employees
UNION
SELECT skill, 'Маркетинг' as department FROM marketing_employees
ORDER BY skill;
```

## 2. EXCEPT - Разность множеств

**EXCEPT** возвращает строки из первого запроса, которых **нет во втором**.

```sql
-- Сотрудники только из ИТ отдела (не работают в маркетинге)
SELECT first_name, last_name FROM it_employees
EXCEPT
SELECT first_name, last_name FROM marketing_employees;
```

**Результат:**
| first_name | last_name |
|------------|-----------|
| Иван | Петров |
| Мария | Сидорова |
| Елена | Морозова |

### Практический пример EXCEPT

```sql
-- Навыки, которые есть только в ИТ
SELECT skill FROM it_employees
EXCEPT
SELECT skill FROM marketing_employees;
```

**Результат:** Python, Java

## 3. INTERSECT - Пересечение множеств

**INTERSECT** возвращает строки, которые **есть в обоих** запросах.

```sql
-- Сотрудники, работающие в обоих отделах
SELECT first_name, last_name FROM it_employees
INTERSECT
SELECT first_name, last_name FROM marketing_employees;
```

**Результат:**
| first_name | last_name |
|------------|-----------|
| Алексей | Козлов |

### Практический пример INTERSECT

```sql
-- Навыки, которые есть в обоих отделах
SELECT skill FROM it_employees
INTERSECT
SELECT skill FROM marketing_employees;
```

**Результат:** SQL

## Комплексные примеры

### Пример 1: Анализ навыков

```sql
-- Сравнение навыков между отделами
SELECT 'Только ИТ' as category, skill FROM it_employees
EXCEPT
SELECT 'Только ИТ', skill FROM marketing_employees

UNION ALL

SELECT 'Только Маркетинг', skill FROM marketing_employees
EXCEPT
SELECT 'Только Маркетинг', skill FROM it_employees

UNION ALL

SELECT 'Общие навыки', skill FROM it_employees
INTERSECT
SELECT 'Общие навыки', skill FROM marketing_employees;
```

### Пример 2: Статистика по отделам

```sql
-- Количество уникальных сотрудников
SELECT 'Всего уникальных' as metric, COUNT(*) as count FROM (
    SELECT first_name, last_name FROM it_employees
    UNION
    SELECT first_name, last_name FROM marketing_employees
) t

UNION ALL

SELECT 'Работают в двух отделах', COUNT(*) FROM (
    SELECT first_name, last_name FROM it_employees
    INTERSECT
    SELECT first_name, last_name FROM marketing_employees
) t;
```

## Важные правила

1. **Количество столбцов** должно совпадать
2. **Типы данных** должны быть совместимы
3. **Порядок столбцов** имеет значение
4. **ORDER BY** применяется к итоговому результату

```sql
-- Правильно
SELECT first_name, last_name FROM it_employees
UNION
SELECT first_name, last_name FROM marketing_employees
ORDER BY last_name;

-- Неправильно - разное количество столбцов
SELECT first_name, last_name, skill FROM it_employees
UNION
SELECT first_name, last_name FROM marketing_employees;
```

## Практические задания

### Задание 1: Найти сотрудников только из ИТ

```sql
SELECT first_name, last_name FROM it_employees
EXCEPT
SELECT first_name, last_name FROM marketing_employees;
```

### Задание 2: Все навыки в компании

```sql
SELECT skill FROM it_employees
UNION
SELECT skill FROM marketing_employees;
```

### Задание 3: Универсальные сотрудники

```sql
SELECT first_name, last_name FROM it_employees
INTERSECT
SELECT first_name, last_name FROM marketing_employees;
```

## Производительность

- **UNION** медленнее **UNION ALL** (удаляет дубликаты)
- **INTERSECT** и **EXCEPT** требуют сортировки
- Используйте индексы на столбцах сравнения
- Для больших таблиц рассмотрите альтернативы с JOIN

```sql
-- Альтернатива INTERSECT через JOIN
SELECT DISTINCT i.first_name, i.last_name
FROM it_employees i
JOIN marketing_employees m ON i.first_name = m.first_name 
                           AND i.last_name = m.last_name;
```

## Выводы

**Операции с множествами полезны для:**
- Анализа пересечений данных
- Поиска уникальных записей
- Объединения результатов из разных источников
- Сравнения наборов данных

**Используйте осторожно:**
- Проверяйте совместимость типов данных
- Учитывайте производительность на больших данных
- Помните о порядке столбцов