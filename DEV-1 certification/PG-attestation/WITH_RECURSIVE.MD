# Иерархические запросы в PostgreSQL с использованием WITH RECURSIVE

В PostgreSQL для работы с иерархическими данными (деревьями, графами) используется конструкция `WITH RECURSIVE` в сочетании с `UNION ALL`. Это мощный инструмент для обработки рекурсивных структур данных.

## Базовый синтаксис

```sql
WITH RECURSIVE recursive_query_name AS (
    -- Не рекурсивная часть (начальное условие)
    SELECT initial_columns
    FROM initial_table
    WHERE initial_condition
    
    UNION ALL
    
    -- Рекурсивная часть
    SELECT recursive_columns
    FROM recursive_table
    JOIN recursive_query_name ON join_condition
    WHERE recursive_condition
)
SELECT * FROM recursive_query_name;
```

## Основные компоненты

1. **Не рекурсивная часть** - определяет начальные строки (корни дерева)
2. **UNION ALL** - объединяет результаты
3. **Рекурсивная часть** - ссылается на сам запрос, строя иерархию

## Пример 1: Иерархия сотрудников

Допустим, есть таблица employees с полями id, name и manager_id:

```sql
WITH RECURSIVE employee_hierarchy AS (
    -- Базовый случай: начальники (у которых нет менеджера)
    SELECT id, name, manager_id, 1 AS level
    FROM employees
    WHERE manager_id IS NULL
    
    UNION ALL
    
    -- Рекурсивный случай: подчиненные
    SELECT e.id, e.name, e.manager_id, eh.level + 1
    FROM employees e
    JOIN employee_hierarchy eh ON e.manager_id = eh.id
)
SELECT id, name, level FROM employee_hierarchy
ORDER BY level, name;
```

## Пример 2: Дерево категорий

Для таблицы categories с полями id, name, parent_id:

```sql
WITH RECURSIVE category_tree AS (
    -- Базовый случай: корневые категории
    SELECT id, name, parent_id, ARRAY[name] AS path
    FROM categories
    WHERE parent_id IS NULL
    
    UNION ALL
    
    -- Рекурсивный случай: дочерние категории
    SELECT c.id, c.name, c.parent_id, ct.path || c.name
    FROM categories c
    JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT id, name, array_to_string(path, ' > ') AS full_path
FROM category_tree
ORDER BY path;
```

## Пример 3: Поиск путей в графе

Для таблицы graph с полями source, target, weight:

```sql
WITH RECURSIVE paths AS (
    -- Базовый случай: пути длиной 1
    SELECT source, target, weight, ARRAY[source, target] AS path
    FROM graph
    
    UNION ALL
    
    -- Рекурсивный случай: удлинение путей
    SELECT p.source, g.target, p.weight + g.weight, p.path || g.target
    FROM paths p
    JOIN graph g ON p.target = g.source
    WHERE NOT g.target = ANY(p.path) -- избегаем циклов
)
SELECT * FROM paths
WHERE source = 1 AND target = 5
ORDER BY weight;
```

## Важные особенности

1. **Условие остановки** - рекурсия прекращается, когда рекурсивная часть не возвращает строк
2. **Предотвращение циклов** - важно добавить проверку (как в примере 3)
3. **Глубина рекурсии** - PostgreSQL имеет лимит (по умолчанию 100), который можно изменить: `SET max_recursive_iterations TO 500;`

## Оптимизация производительности

1. Используйте индексы на соединяемых столбцах
2. Добавляйте условия WHERE в рекурсивную часть для ранней фильтрации
3. Для больших иерархий рассмотрите материализацию промежуточных результатов

Рекурсивные запросы - мощный инструмент для работы с иерархическими данными, который позволяет решать сложные задачи средствами SQL.


# Рекурсивный факториал

```sql
WITH RECURSIVE t(n,factorial) AS (
  VALUES (0,1)
  UNION ALL
  SELECT t.n+1, t.factorial*(t.n+1) FROM t WHERE t.n < 10
)
SELECT * FROM t;
```

# Рекурсивный фибоначи
```sql
WITH RECURSIVE fibonacci(n, fib_n, next_fib) AS (
    -- Базовый случай: первые два числа Фибоначчи
    SELECT 1, 0, 1    
    UNION ALL       
    SELECT n + 1, next_fib, fib_n + next_fib
    FROM fibonacci
    WHERE n < 20 -- Ограничиваем количество итераций
)
SELECT n, fib_n AS fibonacci_number
FROM fibonacci
ORDER BY n;
```