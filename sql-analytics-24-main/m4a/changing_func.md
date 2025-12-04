# Категории изменчивости функций в PostgreSQL

## Введение

PostgreSQL классифицирует функции по их **изменчивости** (volatility) — насколько предсказуемы результаты функции при одинаковых входных параметрах. Это влияет на оптимизацию запросов и возможность использования функций в индексах.

---

## VOLATILE — Изменчивые функции

### Определение
**VOLATILE** функции могут возвращать разные результаты при одинаковых входных параметрах. Это категория по умолчанию.

### Характеристики
- Результат может меняться между вызовами
- Могут изменять состояние базы данных
- Не кешируются оптимизатором
- Не могут использоваться в функциональных индексах

### Примеры VOLATILE функций

```sql
-- Функции времени и даты
SELECT NOW();           -- каждый раз новое время
SELECT RANDOM();        -- случайное число
SELECT CURRVAL('seq');  -- текущее значение последовательности

-- Функции изменения данных
SELECT NEXTVAL('seq');  -- изменяет состояние последовательности
```

### Создание VOLATILE функции

```sql
-- Функция генерации случайного ID
CREATE OR REPLACE FUNCTION generate_random_id()
RETURNS TEXT
LANGUAGE sql
VOLATILE  -- явно указываем (можно опустить, т.к. по умолчанию)
RETURN 'ID_' || FLOOR(RANDOM() * 1000000)::TEXT;

-- Каждый вызов возвращает новое значение
SELECT generate_random_id();  -- ID_123456
SELECT generate_random_id();  -- ID_789012
```

### Функция с изменением состояния

```sql
-- Счетчик вызовов
CREATE TABLE function_calls (
    function_name TEXT,
    call_count INTEGER DEFAULT 0
);

INSERT INTO function_calls VALUES ('my_counter', 0);

CREATE OR REPLACE FUNCTION increment_counter()
RETURNS INTEGER
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    new_count INTEGER;
BEGIN
    UPDATE function_calls 
    SET call_count = call_count + 1 
    WHERE function_name = 'my_counter'
    RETURNING call_count INTO new_count;
    
    RETURN new_count;
END;
$$;

-- Каждый вызов увеличивает счетчик
SELECT increment_counter();  -- 1
SELECT increment_counter();  -- 2
SELECT increment_counter();  -- 3
```

---

## STABLE — Стабильные функции

### Определение
**STABLE** функции возвращают одинаковый результат для одинаковых параметров **в пределах одного SQL-оператора**.

### Характеристики
- Результат не меняется в рамках одного запроса
- Не могут изменять состояние базы данных
- Могут кешироваться в пределах запроса
- Могут читать из базы данных

### Примеры STABLE функций

```sql
-- Функции, зависящие от времени транзакции
SELECT CURRENT_DATE;        -- дата не меняется в рамках транзакции
SELECT CURRENT_TIMESTAMP;   -- время транзакции
SELECT CURRENT_USER;        -- текущий пользователь
```

### Создание STABLE функции

```sql
-- Функция получения курса валют (в рамках запроса не меняется)
CREATE TABLE exchange_rates (
    currency_code TEXT PRIMARY KEY,
    rate_to_usd NUMERIC,
    updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO exchange_rates VALUES 
('EUR', 0.85, NOW()),
('RUB', 75.50, NOW()),
('GBP', 0.73, NOW());

CREATE OR REPLACE FUNCTION get_exchange_rate(currency TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    rate NUMERIC;
BEGIN
    SELECT rate_to_usd INTO rate
    FROM exchange_rates
    WHERE currency_code = currency;
    
    RETURN COALESCE(rate, 1.0);  -- USD по умолчанию
END;
$$;

-- В рамках одного запроса результат кешируется
SELECT 
    product_name,
    price_usd,
    price_usd * get_exchange_rate('EUR') AS price_eur,
    price_usd * get_exchange_rate('RUB') AS price_rub
FROM (VALUES 
    ('Товар 1', 100),
    ('Товар 2', 200)
) AS products(product_name, price_usd);
```

### Функция с зависимостью от времени транзакции

```sql
-- Функция возраста на момент транзакции
CREATE OR REPLACE FUNCTION calculate_age(birth_date DATE)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXTRACT(YEAR FROM AGE(CURRENT_DATE, birth_date));
END;
$$;

-- В рамках одного запроса возраст не изменится
SELECT 
    name,
    birth_date,
    calculate_age(birth_date) AS age
FROM (VALUES 
    ('Иван', '1990-05-15'::DATE),
    ('Мария', '1985-12-03'::DATE)
) AS people(name, birth_date);
```

---

## IMMUTABLE — Неизменяемые функции

### Определение
**IMMUTABLE** функции всегда возвращают одинаковый результат для одинаковых входных параметров.

### Характеристики
- Полностью детерминированы
- Не могут изменять состояние базы данных
- Не могут читать из базы данных
- Могут использоваться в функциональных индексах
- Агрессивно кешируются оптимизатором

### Примеры IMMUTABLE функций

```sql
-- Математические функции
SELECT ABS(-5);         -- всегда 5
SELECT SQRT(16);        -- всегда 4
SELECT UPPER('hello');  -- всегда 'HELLO'
SELECT LENGTH('text');  -- всегда 4
```

### Создание IMMUTABLE функции

```sql
-- Функция вычисления НДС
CREATE OR REPLACE FUNCTION calculate_vat(amount NUMERIC, rate NUMERIC DEFAULT 0.20)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN ROUND(amount * rate, 2);
END;
$$;

-- Результат всегда одинаковый для одинаковых параметров
SELECT calculate_vat(1000);     -- всегда 200.00
SELECT calculate_vat(1000, 0.18); -- всегда 180.00
```

### Функция форматирования

```sql
-- Функция форматирования телефона
CREATE OR REPLACE FUNCTION format_phone(phone_digits TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF LENGTH(phone_digits) = 11 AND phone_digits ~ '^[0-9]+$' THEN
        RETURN '+7 (' || SUBSTRING(phone_digits, 2, 3) || ') ' ||
               SUBSTRING(phone_digits, 5, 3) || '-' ||
               SUBSTRING(phone_digits, 8, 2) || '-' ||
               SUBSTRING(phone_digits, 10, 2);
    ELSE
        RETURN phone_digits;  -- возвращаем как есть, если формат неверный
    END IF;
END;
$$;

-- Всегда одинаковый результат
SELECT format_phone('79161234567');  -- +7 (916) 123-45-67
```

---

## Практические примеры и сравнения

### Демонстрация различий

```sql
-- Создаем таблицу для тестирования
CREATE TABLE test_data (
    id SERIAL PRIMARY KEY,
    value NUMERIC
);

INSERT INTO test_data (value) VALUES (10), (20), (30);

-- VOLATILE: каждый раз новый результат
CREATE OR REPLACE FUNCTION volatile_func(x NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    RETURN x + RANDOM() * 100;
END;
$$;

-- STABLE: одинаковый результат в рамках запроса
CREATE OR REPLACE FUNCTION stable_func(x NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN x + EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)::INTEGER % 1000;
END;
$$;

-- IMMUTABLE: всегда одинаковый результат
CREATE OR REPLACE FUNCTION immutable_func(x NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN x * 2 + 5;
END;
$$;

-- Тестирование
SELECT 
    id,
    value,
    volatile_func(value) AS volatile_result,    -- разные значения
    stable_func(value) AS stable_result,        -- одинаковые в запросе
    immutable_func(value) AS immutable_result   -- всегда одинаковые
FROM test_data;
```

### Использование в индексах

```sql
-- Только IMMUTABLE функции можно использовать в индексах
CREATE INDEX idx_test_immutable ON test_data (immutable_func(value));

-- Это вызовет ошибку:
-- CREATE INDEX idx_test_volatile ON test_data (volatile_func(value));
-- CREATE INDEX idx_test_stable ON test_data (stable_func(value));

-- Поиск с использованием функционального индекса
SELECT * FROM test_data WHERE immutable_func(value) = 25;
```

---

## Влияние на производительность

### Кеширование результатов

```sql
-- Создаем "тяжелую" функцию для демонстрации
CREATE OR REPLACE FUNCTION heavy_calculation(n INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE  -- позволяет кеширование
AS $$
DECLARE
    result INTEGER := 0;
    i INTEGER;
BEGIN
    -- Имитация сложных вычислений
    FOR i IN 1..n LOOP
        result := result + i;
    END LOOP;
    RETURN result;
END;
$$;

-- В этом запросе функция вызовется только один раз для каждого уникального значения
SELECT 
    generate_series(1, 5) AS n,
    heavy_calculation(3) AS calc_result;  -- вычислится только один раз

-- Если бы функция была VOLATILE, вычислялась бы каждый раз
```

### Оптимизация запросов

```sql
-- IMMUTABLE функции могут быть вычислены на этапе планирования
EXPLAIN (COSTS OFF) 
SELECT * FROM test_data 
WHERE value > immutable_func(5);  -- immutable_func(5) вычислится заранее

-- VOLATILE функции вычисляются каждый раз
EXPLAIN (COSTS OFF)
SELECT * FROM test_data 
WHERE value > volatile_func(5);   -- будет вычисляться для каждой строки
```

---

## Рекомендации по выбору категории

### Когда использовать VOLATILE
- Функции с побочными эффектами (INSERT, UPDATE, DELETE)
- Функции, зависящие от внешних факторов (файлы, сеть)
- Генераторы случайных значений
- Функции времени реального времени

```sql
-- Примеры VOLATILE функций
CREATE OR REPLACE FUNCTION log_access(user_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    INSERT INTO access_log (user_id, access_time) VALUES (user_id, NOW());
END;
$$;
```

### Когда использовать STABLE
- Функции, читающие из базы данных
- Функции, зависящие от параметров сессии/транзакции
- Функции конфигурации

```sql
-- Примеры STABLE функций
CREATE OR REPLACE FUNCTION get_user_setting(setting_name TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    setting_value TEXT;
BEGIN
    SELECT value INTO setting_value
    FROM user_settings
    WHERE user_id = current_setting('app.current_user_id')::INTEGER
      AND name = setting_name;
    
    RETURN setting_value;
END;
$$;
```

### Когда использовать IMMUTABLE
- Чистые математические функции
- Функции форматирования и валидации
- Функции преобразования данных

```sql
-- Примеры IMMUTABLE функций
CREATE OR REPLACE FUNCTION slugify(input_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN LOWER(
        REGEXP_REPLACE(
            REGEXP_REPLACE(input_text, '[^a-zA-Z0-9\s-]', '', 'g'),
            '\s+', '-', 'g'
        )
    );
END;
$$;
```

---

## Изменение категории функции

```sql
-- Изменение существующей функции
ALTER FUNCTION calculate_vat(NUMERIC, NUMERIC) IMMUTABLE;
ALTER FUNCTION get_exchange_rate(TEXT) STABLE;
ALTER FUNCTION generate_random_id() VOLATILE;

-- Проверка текущей категории
SELECT 
    proname AS function_name,
    CASE provolatile
        WHEN 'i' THEN 'IMMUTABLE'
        WHEN 's' THEN 'STABLE'
        WHEN 'v' THEN 'VOLATILE'
    END AS volatility
FROM pg_proc
WHERE proname IN ('calculate_vat', 'get_exchange_rate', 'generate_random_id');
```

---

## Заключение

Правильная классификация функций по изменчивости критически важна для:

- **Производительности** — IMMUTABLE функции кешируются агрессивно
- **Индексов** — только IMMUTABLE функции можно использовать в функциональных индексах
- **Оптимизации** — планировщик может лучше оптимизировать запросы
- **Корректности** — неправильная категория может привести к неожиданным результатам

### Правила выбора:
1. **IMMUTABLE** — если результат зависит только от входных параметров
2. **STABLE** — если результат может зависеть от состояния БД, но стабилен в рамках запроса
3. **VOLATILE** — если результат может меняться или функция имеет побочные эффекты

**Важно:** Лучше выбрать более ограничительную категорию (VOLATILE вместо STABLE), чем менее ограничительную, если есть сомнения.