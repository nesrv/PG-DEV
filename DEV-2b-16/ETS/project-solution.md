Проет  **List Partitioning** 
---

### **Задача: Автоматическое создание партиций для новых статусов заказов**  
**Условие:**  
У вас есть таблица `orders`, партиционированная по списку (`status`). Партиции созданы для статусов `'new'`, `'processing'`, `'done'`, а все остальные статусы попадают в `DEFAULT`-партицию.  

**Проблема:**  
При появлении нового статуса (например, `'returned'`) записи автоматически попадают в `DEFAULT`, что может замедлить查询. Нужно **автоматически создавать партицию** для нового статуса, если он встречается чаще 100 раз, и **перемещать** данные из `DEFAULT` в новую партицию.

---

### **Решение**  
1. **Создадим таблицу и партиции:**
```sql
CREATE TABLE orders (
    id SERIAL,
    customer_name TEXT,
    status TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
) PARTITION BY LIST (status);

-- Известные партиции
CREATE TABLE orders_new PARTITION OF orders FOR VALUES IN ('new');
CREATE TABLE orders_processing PARTITION OF orders FOR VALUES IN ('processing');
CREATE TABLE orders_done PARTITION OF orders FOR VALUES IN ('done');
CREATE TABLE orders_other PARTITION OF orders DEFAULT;
```

2. **Функция для автоматического создания партиций:**  
   Проверяет, если какой-то статус в `DEFAULT` встречается > 100 раз — создаёт для него партицию.
```sql
CREATE OR REPLACE FUNCTION create_partition_for_new_status()
RETURNS TRIGGER AS $$
DECLARE
    new_status TEXT;
    partition_name TEXT;
    query TEXT;
BEGIN
    -- Находим статусы в DEFAULT-партиции, которые встречаются > 100 раз
    FOR new_status IN 
        SELECT status FROM orders_other GROUP BY status HAVING COUNT(*) > 100
    LOOP
        partition_name := 'orders_' || REPLACE(LOWER(new_status), ' ', '_');
        
        -- Создаём партицию, если её ещё нет
        IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = partition_name) THEN
            query := format('CREATE TABLE %I PARTITION OF orders FOR VALUES IN (%L)', 
                            partition_name, new_status);
            EXECUTE query;
            
            -- Перемещаем данные из DEFAULT в новую партицию
            query := format('WITH moved_rows AS (
                               DELETE FROM ONLY orders_other 
                               WHERE status = %L 
                               RETURNING *
                           )
                           INSERT INTO %I SELECT * FROM moved_rows', 
                           new_status, partition_name);
            EXECUTE query;
            
            RAISE NOTICE 'Создана партиция % для статуса %', partition_name, new_status;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

3. **Триггер, запускающий функцию при вставке:**  
```sql
CREATE TRIGGER check_new_status_trigger
AFTER INSERT ON orders
EXECUTE FUNCTION create_partition_for_new_status();
```

4. **Тестирование:**  
   - Вставим 101 заказ с новым статусом `'returned'`:
   ```sql
   INSERT INTO orders (customer_name, status)
   SELECT 'Customer ' || i, 'returned'
   FROM generate_series(1, 101) AS i;
   ```
   - Проверим, что партиция `orders_returned` создана автоматически:
   ```sql
   SELECT * FROM orders_returned;  -- Должно быть 101 запись
   SELECT * FROM orders_other;     -- Здесь их уже нет
   ```

---

### **Дополнительные оптимизации**  
1. **Ручное управление партициями через cron-задачу:**  
   Если триггер на каждую вставку слишком затратен, можно заменить его на ежечасный вызов функции через `pg_cron`:
   ```sql
   SELECT cron.schedule('0 * * * *', $$SELECT create_partition_for_new_status()$$);
   ```

2. **Ограничение на частые статусы:**  
   Добавить индекс в `DEFAULT`-партицию для ускорения поиска перед перемещением:
   ```sql
   CREATE INDEX idx_orders_other_status ON orders_other (status);
   ```

---

### **Итог**  
Это решение:  
- Автоматически создаёт партиции для «горячих» новых статусов.  
- Избегает разрастания `DEFAULT`-партиции.  
- Сочетает триггеры и cron для баланса между скоростью и нагрузкой.  

Подходит для систем, где статусы заказов часто расширяются (например, маркетплейсы).