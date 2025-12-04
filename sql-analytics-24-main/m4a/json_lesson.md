# Работа с JSON и JSONB в PostgreSQL

## Введение

PostgreSQL поддерживает два типа данных для работы с JSON:
- **JSON** — текстовое хранение, точное сохранение формата
- **JSONB** — бинарное хранение, оптимизированное для запросов

## Создание тестовых данных

```sql
-- Создаем таблицу с JSON данными
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    info JSON,           -- JSON тип
    metadata JSONB       -- JSONB тип (рекомендуется)
);

-- Вставляем тестовые данные
INSERT INTO products (name, info, metadata) VALUES
('YotaPhone 3', 
 '{"brand": "Yota", "price": 45000, "specs": {"storage": "128GB", "color": "black"}}',
 '{"category": "smartphone", "tags": ["premium", "dual-screen"], "available": true}'
),
('Эльбрус Планшет', 
 '{"brand": "МЦСТ", "price": 35000, "specs": {"storage": "64GB", "color": "silver"}}',
 '{"category": "tablet", "tags": ["отечественный", "безопасность"], "available": false}'
),
('Аквариус Ноутбук',
 '{"brand": "Аквариус", "price": 85000, "specs": {"ram": "8GB", "cpu": "Байкал"}}',
 '{"category": "laptop", "tags": ["российский", "офисный"], "available": true}'
);
```

---

## Основные операторы доступа

### Оператор -> (возвращает JSON)
```sql
-- Получение JSON объекта
SELECT name, info->'brand' AS brand_json FROM products;
-- Результат: "Yota", "МЦСТ", "Аквариус"

-- Доступ к вложенным объектам
SELECT name, info->'specs'->'storage' AS storage_json FROM products;
-- Результат: "128GB", "256GB", null
```

### Оператор ->> (возвращает TEXT)
```sql
-- Получение текстового значения
SELECT name, info->>'brand' AS brand_text FROM products;
-- Результат: Apple, Samsung, Apple

-- Приведение к числу
SELECT name, (info->>'price')::INTEGER AS price FROM products;
-- Результат: YotaPhone 3 | 45000
```

### Оператор #> (путь как массив)
```sql
-- Доступ по пути
SELECT name, info #> '{specs,storage}' AS storage FROM products;

-- Текстовый результат
SELECT name, info #>> '{specs,storage}' AS storage_text FROM products;
```

---

## Поиск и фильтрация

### Проверка существования ключей
```sql
-- Проверка наличия ключа
SELECT name FROM products WHERE info::JSONB ? 'brand';

-- Проверка наличия любого из ключей
SELECT name FROM products WHERE metadata ?| ARRAY['tags', 'category'];

-- Проверка наличия всех ключей
SELECT name FROM products WHERE metadata ?& ARRAY['category', 'available'];
```

### Поиск по значениям
```sql
-- Точное совпадение
SELECT name FROM products WHERE info->>'brand' = 'Apple';

-- Поиск в массивах
SELECT name FROM products WHERE metadata->'tags' ? 'premium';

-- Содержит объект/массив
SELECT name FROM products WHERE metadata @> '{"available": true}';
SELECT name FROM products WHERE metadata @> '{"tags": ["premium"]}';
```

### JSONPath запросы (PostgreSQL 12+)
```sql
-- Использование JSONPath
SELECT name FROM products WHERE metadata @@ '$.available == true';
SELECT name FROM products WHERE metadata @@ '$.tags[*] == "premium"';
SELECT name FROM products WHERE info @@ '$.price > 70000';
```

---

## Модификация JSON данных

### Обновление значений
```sql
-- Обновление простого значения
UPDATE products 
SET metadata = jsonb_set(metadata, '{available}', 'false')
WHERE name = 'YotaPhone 3';

-- Обновление вложенного значения
UPDATE products
SET info = jsonb_set(info, '{specs,storage}', '"256GB"')
WHERE name = 'YotaPhone 3';

-- Добавление нового ключа
UPDATE products
SET metadata = jsonb_set(metadata, '{warranty}', '"3 года"')
WHERE name = 'Аквариус Ноутбук';
```

### Добавление и объединение
```sql
-- Объединение JSON объектов
UPDATE products
SET metadata = metadata || '{"discount": 15, "new_feature": true}'
WHERE name = 'Эльбрус Планшет';

-- Добавление элемента в массив
UPDATE products
SET metadata = jsonb_set(
    metadata, 
    '{tags}', 
    (metadata->'tags') || '["инновационный"]'
)
WHERE name = 'YotaPhone 3';
```

### Удаление данных
```sql
-- Удаление ключа
UPDATE products SET metadata = metadata - 'discount' WHERE name = 'Эльбрус Планшет';

-- Удаление по пути
UPDATE products SET metadata = metadata #- '{tags,0}' WHERE name = 'YotaPhone 3';

-- Удаление нескольких ключей
UPDATE products SET metadata = metadata - ARRAY['warranty', 'new_feature'];
```

---

## JSON функции

### Извлечение данных
```sql
-- Получение всех ключей
SELECT name, jsonb_object_keys(metadata) AS keys FROM products;

-- Разворачивание в строки
SELECT name, key, value 
FROM products, jsonb_each_text(metadata);

-- Получение массива значений
SELECT name, jsonb_array_elements_text(metadata->'tags') AS tag
FROM products
WHERE metadata ? 'tags';
```

### Агрегация JSON
```sql
-- Сбор в массив
SELECT jsonb_agg(name) AS all_products FROM products;

-- Создание объекта
SELECT jsonb_object_agg(name, info->>'price') AS price_list FROM products;

-- Группировка
SELECT 
    info->>'brand' AS brand,
    jsonb_agg(name) AS products
FROM products 
GROUP BY info->>'brand';
```

### Построение JSON
```sql
-- Создание JSON объекта
SELECT json_build_object(
    'product_name', name,
    'brand', info->>'brand',
    'price', (info->>'price')::INTEGER,
    'in_stock', metadata->>'available'
) AS product_summary
FROM products;

-- Создание JSON массива
SELECT json_build_array(name, info->>'brand', info->>'price') AS product_array
FROM products;
```

---

## Практические примеры

### Пример 1: Каталог товаров
```sql
-- Поиск товаров по категории и наличию
SELECT 
    name,
    info->>'brand' AS brand,
    (info->>'price')::INTEGER AS price,
    metadata->'tags' AS tags
FROM products
WHERE metadata->>'category' = 'smartphone'
  AND metadata->>'available' = 'true';

-- Товары с определенными тегами
SELECT name, metadata->'tags' AS tags
FROM products
WHERE metadata->'tags' ?| ARRAY['premium', 'professional'];
```

### Пример 2: Статистика по брендам
```sql
-- Количество товаров и средняя цена по брендам
SELECT 
    info->>'brand' AS brand,
    COUNT(*) AS product_count,
    AVG((info->>'price')::INTEGER) AS avg_price,
    jsonb_agg(name) AS products
FROM products
GROUP BY info->>'brand';
```

### Пример 3: Обновление цен
```sql
-- Увеличение цены на 10% для товаров Yota
UPDATE products
SET info = jsonb_set(
    info, 
    '{price}', 
    ((info->>'price')::INTEGER * 1.1)::TEXT::JSONB
)
WHERE info->>'brand' = 'Yota';
```

### Пример 4: Сложные фильтры
```sql
-- Товары дороже 70000 с тегом "premium" или "professional"
SELECT name, info->>'price' AS price, metadata->'tags' AS tags
FROM products
WHERE (info->>'price')::INTEGER > 70000
  AND (metadata->'tags' ? 'premium' OR metadata->'tags' ? 'professional');
```

---

## Индексы для JSON

### GIN индексы
```sql
-- Индекс для JSONB (рекомендуется)
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Индекс для конкретного пути
CREATE INDEX idx_products_category ON products ((metadata->>'category'));

-- Составной индекс
CREATE INDEX idx_products_brand_price ON products (
    (info->>'brand'), 
    ((info->>'price')::INTEGER)
);
```

### Использование индексов
```sql
-- Эти запросы будут использовать индексы
SELECT * FROM products WHERE metadata @> '{"available": true}';
SELECT * FROM products WHERE metadata->>'category' = 'smartphone';
SELECT * FROM products WHERE info->>'brand' = 'Yota';
```

---

## Валидация JSON

### Проверка корректности
```sql
-- Функция для проверки JSON
CREATE OR REPLACE FUNCTION is_valid_json(json_text TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    PERFORM json_text::JSON;
    RETURN TRUE;
EXCEPTION
    WHEN invalid_text_representation THEN
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Использование
SELECT is_valid_json('{"valid": "json"}');  -- true
SELECT is_valid_json('{invalid json}');     -- false
```

### JSON Schema валидация (расширение)
```sql
-- Установка расширения (если доступно)
-- CREATE EXTENSION IF NOT EXISTS jsonschema;

-- Пример схемы
/*
SELECT jsonschema_is_valid(
    '{"type": "object", "properties": {"name": {"type": "string"}}}',
    '{"name": "test"}'
);
*/
```

---

## Производительность: JSON vs JSONB

### Сравнение типов
| Аспект | JSON | JSONB |
|--------|------|-------|
| Хранение | Текст | Бинарный формат |
| Вставка | Быстрее | Медленнее (парсинг) |
| Запросы | Медленнее | Быстрее |
| Индексы | Ограниченно | Полная поддержка |
| Порядок ключей | Сохраняется | Не сохраняется |
| Дубликаты ключей | Сохраняются | Удаляются |

### Рекомендации
```sql
-- Используйте JSONB для:
-- - Частых запросов и фильтрации
-- - Индексирования
-- - Сложных операций с JSON

-- Используйте JSON для:
-- - Логирования (сохранение точного формата)
-- - Временного хранения
-- - Когда важен порядок ключей
```

---

## Миграция JSON → JSONB

```sql
-- Добавление нового столбца JSONB
ALTER TABLE products ADD COLUMN info_jsonb JSONB;

-- Копирование данных
UPDATE products SET info_jsonb = info::JSONB;

-- Создание индекса
CREATE INDEX idx_products_info_jsonb ON products USING GIN (info_jsonb);

-- Удаление старого столбца (после тестирования)
-- ALTER TABLE products DROP COLUMN info;
-- ALTER TABLE products RENAME COLUMN info_jsonb TO info;
```

---

## Заключение

**Ключевые принципы работы с JSON в PostgreSQL:**

1. **Выбирайте JSONB** для большинства случаев
2. **Создавайте GIN индексы** для часто используемых путей
3. **Используйте операторы** `@>`, `?`, `?|`, `?&` для эффективного поиска
4. **Валидируйте данные** на уровне приложения
5. **Группируйте изменения** в одном UPDATE для производительности

**Типичные паттерны:**
- Конфигурации приложений
- Метаданные продуктов
- Логи и события
- Пользовательские настройки
- API ответы и кеширование