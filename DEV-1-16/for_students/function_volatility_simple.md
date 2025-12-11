# 🎭 Типы функций PostgreSQL: Простые примеры

## 🌪️ VOLATILE (Изменчивая)
**Ассоциация:** Погода за окном - каждый раз разная!

```sql
-- Встроенные VOLATILE функции
SELECT NOW();           -- 2024-01-15 14:30:25
SELECT NOW();           -- 2024-01-15 14:30:26 (время изменилось!)

SELECT RANDOM();        -- 0.123456
SELECT RANDOM();        -- 0.789012 (всегда разные числа)

-- Создание простой VOLATILE функции
CREATE FUNCTION get_timestamp() RETURNS TEXT AS 
'SELECT ''Время: '' || NOW()::TEXT' 
LANGUAGE SQL VOLATILE;

SELECT get_timestamp(); -- "Время: 2024-01-15 14:30:25"
SELECT get_timestamp(); -- "Время: 2024-01-15 14:30:26"
```

---

## 🏠 STABLE (Стабильная)
**Ассоциация:** Температура дома - в течение дня одинаковая

```sql
-- Встроенные STABLE функции
SELECT CURRENT_DATE;    -- 2024-01-15
SELECT CURRENT_USER;    -- postgres

-- В одном запросе всегда одинаково
SELECT NOW(), NOW(), NOW(); -- Все три значения одинаковые!

-- Создание STABLE функции
CREATE FUNCTION get_today() RETURNS TEXT AS 
'SELECT ''Сегодня: '' || CURRENT_DATE::TEXT' 
LANGUAGE SQL STABLE;

-- В одном запросе результат одинаковый
SELECT get_today(), get_today(); -- "Сегодня: 2024-01-15", "Сегодня: 2024-01-15"
```

---

## 💎 IMMUTABLE (Неизменная)
**Ассоциация:** Математические константы - никогда не меняются

```sql
-- Встроенные IMMUTABLE функции
SELECT ABS(-5);         -- Всегда 5
SELECT UPPER('hello');  -- Всегда 'HELLO'
SELECT LENGTH('text');  -- Всегда 4

-- Создание IMMUTABLE функции
CREATE FUNCTION circle_area(radius NUMERIC) RETURNS NUMERIC AS 
'SELECT 3.14159 * $1 * $1' 
LANGUAGE SQL IMMUTABLE;

SELECT circle_area(5);  -- Всегда 78.53975
SELECT circle_area(5);  -- Всегда 78.53975
```

---

## 🎯 Практическая таблица

| Тип | Примеры функций | Когда результат меняется |
|-----|-----------------|--------------------------|
| **VOLATILE** | `NOW()`, `RANDOM()`, `NEXTVAL()` | При каждом вызове |
| **STABLE** | `CURRENT_DATE`, `CURRENT_USER` | Между SQL-запросами |
| **IMMUTABLE** | `ABS()`, `UPPER()`, `LENGTH()` | Никогда (при одинаковых параметрах) |

## ⚡ Влияние на производительность

```sql
-- IMMUTABLE - PostgreSQL кэширует результат
SELECT LENGTH(name) FROM users; -- Вычисляет один раз для каждого уникального name

-- VOLATILE - PostgreSQL вычисляет каждый раз  
SELECT RANDOM() FROM users;     -- Миллион разных чисел для миллиона строк
```

## 🔍 Проверка типа функции

```sql
-- Посмотреть тип функции
SELECT proname, provolatile 
FROM pg_proc 
WHERE proname IN ('now', 'abs', 'current_date');

-- v = VOLATILE, s = STABLE, i = IMMUTABLE
```

**Правило:** Выбирайте правильный тип для максимальной производительности! 🚀