# 🎭 Типы функций PostgreSQL: Ассоциативные примеры

## 🌪️ VOLATILE (Изменчивая)
**Ассоциация:** Погода за окном

```sql
-- Как погода - каждый раз разная!
CREATE FUNCTION get_weather() RETURNS TEXT AS $$
BEGIN
    RETURN 'Сегодня: ' || (CASE 
        WHEN random() < 0.3 THEN 'солнечно'
        WHEN random() < 0.6 THEN 'дождь' 
        ELSE 'снег'
    END);
END;
$$ LANGUAGE plpgsql VOLATILE;

-- Каждый вызов - новый результат
SELECT get_weather(); -- "Сегодня: солнечно"
SELECT get_weather(); -- "Сегодня: дождь"
```

**Примеры VOLATILE функций:**
- `NOW()` - текущее время
- `RANDOM()` - случайное число
- `NEXTVAL()` - следующее значение последовательности

---

## 🏠 STABLE (Стабильная)
**Ассоциация:** Температура в доме в течение дня

```sql
-- Как температура дома - в течение дня одинаковая
CREATE FUNCTION get_home_temp() RETURNS INTEGER AS $$
BEGIN
    -- В пределах одного SQL-запроса возвращает одно значение
    RETURN EXTRACT(hour FROM NOW()) + 20; -- 20-23°C
END;
$$ LANGUAGE plpgsql STABLE;

-- В одном запросе всегда одинаково
SELECT get_home_temp(), get_home_temp(); -- 22, 22
-- Но в новом запросе может измениться
```

**Примеры STABLE функций:**
- `CURRENT_DATE` - текущая дата
- `CURRENT_USER` - текущий пользователь
- Функции чтения конфигурации

---

## 💎 IMMUTABLE (Неизменная)
**Ассоциация:** Математические константы

```sql
-- Как π (пи) - всегда 3.14159...
CREATE FUNCTION circle_area(radius NUMERIC) RETURNS NUMERIC AS $$
BEGIN
    RETURN 3.14159 * radius * radius;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Всегда одинаковый результат для одинаковых параметров
SELECT circle_area(5); -- Всегда 78.53975
SELECT circle_area(5); -- Всегда 78.53975
```

**Примеры IMMUTABLE функций:**
- `ABS(-5)` - модуль числа
- `UPPER('hello')` - перевод в верхний регистр
- `LENGTH('text')` - длина строки

---

## 🎯 Практическая аналогия

| Тип | Аналогия | Поведение |
|-----|----------|-----------|
| **VOLATILE** | 🌦️ Погода | Каждый раз разная |
| **STABLE** | 🏠 Температура дома | В течение дня одинаковая |
| **IMMUTABLE** | 💎 Алмаз | Никогда не меняется |

## ⚡ Влияние на производительность

```sql
-- IMMUTABLE - PostgreSQL может кэшировать результат
SELECT expensive_calculation(x) FROM big_table; -- Вычислит один раз!

-- VOLATILE - PostgreSQL вычисляет каждый раз
SELECT random_value() FROM big_table; -- Миллион вызовов!
```

**Правило:** Чем "стабильнее" функция, тем больше оптимизаций может применить PostgreSQL! 🚀