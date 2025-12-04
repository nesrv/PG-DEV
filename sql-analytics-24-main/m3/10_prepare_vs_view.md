# PREPARE vs VIEW в PostgreSQL: сравнение и выбор

## Общее между PREPARE и VIEW

**Общая цель:** Оба механизма предоставляют способы повторного использования SQL-кода

**Что общего:**
- Позволяют сохранить SQL-запрос для многократного использования
- Упрощают сложные запросы
- Повышают безопасность (контроль доступа)
- Улучшают читаемость кода

## Основные различия

| Характеристика | PREPARE | VIEW |
|----------------|---------|------|
| **Время жизни** | Только текущая сессия | Постоянно (до явного удаления) |
| **Область видимости** | Текущая сессия | Все сессии и пользователи |
| **Хранение** | В памяти | На диске в системном каталоге |
| **Параметры** | Поддерживает параметры ($1, $2) | Не поддерживает параметры напрямую |
| **Оптимизация** | План запроса кэшируется | План запроса строится при каждом вызове |
| **Изменения данных** | Не влияют на подготовленный запрос | Автоматически отражают изменения схемы |
| **Права доступа** | Права проверяются при подготовке | Права проверяются при создании и использовании |

## Когда использовать VIEW?

### 1. Постоянные виртуальные таблицы
```sql
-- Создание представления для частого использования
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE is_active = true AND deleted_at IS NULL;

-- Использование как обычной таблицы
SELECT * FROM active_users ORDER BY created_at DESC;
```

### 2. Упрощение сложных запросов
```sql
-- Сложный запрос с джоинами
CREATE VIEW user_orders_summary AS
SELECT 
    u.id as user_id,
    u.username,
    COUNT(o.id) as total_orders,
    SUM(o.amount) as total_amount,
    MAX(o.order_date) as last_order_date
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username;

-- Простое использование
SELECT * FROM user_orders_summary WHERE total_orders > 5;
```

### 3. Контроль доступа к данным
```sql
-- Представление только с публичными данными
CREATE VIEW public_profiles AS
SELECT id, username, first_name, last_name, avatar_url
FROM users
WHERE is_public = true;

-- Предоставление прав только на представление
GRANT SELECT ON public_profiles TO public_user;
```

### 4. Абстракция данных
```sql
-- Скрытие сложной логики
CREATE VIEW monthly_sales AS
SELECT
    DATE_TRUNC('month', sale_date) as month,
    category,
    SUM(amount) as total_sales,
    COUNT(*) as transaction_count
FROM sales
GROUP BY DATE_TRUNC('month', sale_date), category;

-- Простой анализ
SELECT * FROM monthly_sales WHERE month = '2024-01-01';
```

## Когда использовать PREPARE?

### 1. Многократное выполнение в одной сессии
```sql
-- Подготовка запроса для пакетной обработки
PREPARE update_user_status (INT, BOOLEAN) AS
UPDATE users SET is_active = $2 WHERE id = $1 RETURNING *;

-- Массовое обновление
EXECUTE update_user_status (1, true);
EXECUTE update_user_status (2, false);
EXECUTE update_user_status (3, true);
```

### 2. Запросы с параметрами
```sql
-- Поиск с разными параметрами
PREPARE search_users (TEXT, INT) AS
SELECT * FROM users
WHERE 
    (username ILIKE $1 OR $1 IS NULL) AND
    (age >= $2 OR $2 IS NULL);

EXECUTE search_users ('%john%', NULL);
EXECUTE search_users (NULL, 18);
EXECUTE search_users ('%smith%', 25);
```

### 3. Временные сложные запросы
```sql
-- Для аналитической сессии
PREPARE analytics_query (DATE, DATE) AS
WITH daily_stats AS (
    SELECT 
        DATE_TRUNC('day', created_at) as day,
        COUNT(*) as user_count
    FROM users
    WHERE created_at BETWEEN $1 AND $2
    GROUP BY DATE_TRUNC('day', created_at)
)
SELECT 
    day,
    user_count,
    SUM(user_count) OVER (ORDER BY day) as cumulative
FROM daily_stats;

EXECUTE analytics_query ('2024-01-01', '2024-01-31');
```

### 4. Оптимизация производительности
```sql
-- Сложный запрос с кэшированием плана
PREPARE complex_report (INT) AS
SELECT 
    u.department,
    AVG(s.salary) as avg_salary,
    COUNT(e.id) as employee_count
FROM users u
JOIN employees e ON u.id = e.user_id
JOIN salaries s ON e.id = s.employee_id
WHERE u.company_id = $1
GROUP BY u.department
HAVING COUNT(e.id) > 5;

-- Быстрое выполнение с разными company_id
EXECUTE complex_report (1);
EXECUTE complex_report (2);
```

## Комбинирование VIEW и PREPARE

### Мощная комбинация
```sql
-- Создаем VIEW для базовой логики
CREATE VIEW user_activity AS
SELECT 
    u.id,
    u.username,
    COUNT(l.id) as login_count,
    MAX(l.login_time) as last_login
FROM users u
LEFT JOIN user_logins l ON u.id = l.user_id
GROUP BY u.id, u.username;

-- Используем PREPARE для параметризованных запросов
PREPARE active_users_report (INT, DATE) AS
SELECT *
FROM user_activity
WHERE 
    login_count >= $1 AND
    last_login >= $2;

EXECUTE active_users_report (5, '2024-01-01');
```

## Сравнение производительности

### VIEW
- **Плюс:** Автоматически актуализируется при изменении данных
- **Минус:** План запроса строится при каждом обращении
- **Лучше для:** Регулярно меняющихся данных, частых DML-операций

### PREPARE
- **Плюс:** План запроса кэшируется и повторно используется
- **Минус:** Не актуализируется автоматически при изменении данных
- **Лучше для:** Многократного выполнения с разными параметрами

## Практические сценарии

### Сценарий 1: Отчетность
```sql
-- VIEW для базовой структуры отчета
CREATE VIEW sales_report_base AS
SELECT 
    region,
    product_category,
    SUM(amount) as total_sales,
    COUNT(*) as transactions
FROM sales
GROUP BY region, product_category;

-- PREPARE для фильтрации
PREPARE filtered_sales_report (TEXT, TEXT) AS
SELECT *
FROM sales_report_base
WHERE 
    (region = $1 OR $1 IS NULL) AND
    (product_category = $2 OR $2 IS NULL);

EXECUTE filtered_sales_report ('North', NULL);
EXECUTE filtered_sales_report (NULL, 'Electronics');
```

### Сценарий 2: Пользовательские данные
```sql
-- VIEW для безопасности
CREATE VIEW user_private_data AS
SELECT 
    id,
    username,
    email,
    first_name,
    last_name
FROM users
WHERE is_active = true;

-- PREPARE для поиска
PREPARE find_user (TEXT, TEXT) AS
SELECT *
FROM user_private_data
WHERE 
    username ILIKE $1 OR
    email ILIKE $2 OR
    first_name ILIKE $1 OR
    last_name ILIKE $1;

EXECUTE find_user ('%john%', '%john%@%');
```

## Миграция между подходами

### Из PREPARE во VIEW
Когда временный запрос становится постоянным:
```sql
-- Был PREPARE
PREPARE common_query AS SELECT * FROM users WHERE is_active = true;

-- Стал VIEW
CREATE VIEW active_users AS SELECT * FROM users WHERE is_active = true;
```

### Из VIEW в PREPARE
Когда нужны параметры:
```sql
-- Был VIEW (без параметров)
CREATE VIEW recent_orders AS 
SELECT * FROM orders WHERE order_date > CURRENT_DATE - INTERVAL '30 days';

-- Стал PREPARE (с параметром)
PREPARE recent_orders_param (INTERVAL) AS
SELECT * FROM orders WHERE order_date > CURRENT_DATE - $1;
```

## Best Practices

### Используйте VIEW когда:
- ✅ Нужно постоянное представление данных
- ✅ Данные используются в разных сессиях
- ✅ Требуется контроль доступа
- ✅ Нужна абстракция сложной схемы

### Используйте PREPARE когда:
- ✅ Запрос выполняется многократно в одной сессии
- ✅ Нужны параметры для фильтрации
- ✅ Временные аналитические запросы
- ✅ Требуется максимальная производительность

### Избегайте:
- ❌ PREPARE для постоянных структур
- ❌ VIEW для highly-параметризованных запросов
- ❌ Слишком сложных VIEW которые замедляют SELECT
- ❌ PREPARE который не переиспользуется

## Золотые правила

1. **VIEW** — для постоянных виртуальных таблиц
2. **PREPARE** — для временных параметризованных запросов  
3. **Комбинируйте** — используйте VIEW как основу для PREPARE
4. **Тестируйте** — производительность может меняться в разных сценариях