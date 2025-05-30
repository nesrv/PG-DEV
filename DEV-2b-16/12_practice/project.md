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
   
   ... 

END;
$$ LANGUAGE plpgsql;
```

3. **Триггер, запускающий функцию при вставке:**  
```sql
...

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