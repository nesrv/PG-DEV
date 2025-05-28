# Правила RULES



# Пример использования правила (RULE) в PostgreSQL

RULE в PostgreSQL - это механизм перезаписи запросов, который позволяет автоматически преобразовывать входящие SQL-запросы перед их выполнением.

## Пример 1: Простое правило для перенаправления INSERT

Создадим таблицу и правило, которое перенаправляет вставку данных в другую таблицу:

```sql

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    price DECIMAL(10,2)
);


INSERT INTO products (name, price) VALUES 
('Ноутбук', 75000),
('Монитор', 18000),
('Клавиатура', 3500),
('Мышь', 2500),
('Принтер', 12000);


CREATE TABLE products_log (
    id SERIAL PRIMARY KEY,
    product_id INT,
    action VARCHAR(10),
    action_time TIMESTAMP DEFAULT NOW()
);

-- Создаем правило, которое при вставке в products также добавляет запись в лог
CREATE RULE log_insert AS ON INSERT TO products DO ALSO
INSERT INTO products_log (product_id, action) VALUES (NEW.id, 'INSERT');
```

Теперь при вставке в таблицу products:
```sql
INSERT INTO products (name, price) VALUES ('Laptop', 999.99);
```
автоматически будет добавлена запись в таблицу products_log.

## Пример 2: Правило для замены DELETE

Создадим правило, которое заменяет удаление на обновление (имитация "мягкого удаления"):

```sql
-- Добавляем столбец для мягкого удаления
ALTER TABLE products ADD COLUMN is_deleted BOOLEAN DEFAULT FALSE;

-- Создаем правило заменяющее DELETE на UPDATE
CREATE RULE soft_delete AS ON DELETE TO products DO INSTEAD
UPDATE products SET is_deleted = TRUE WHERE id = OLD.id;
```

Теперь при выполнении:
```sql
DELETE FROM products WHERE id = 1;
```
на самом деле будет выполнено обновление, а не удаление.

## Пример 3: Правило для представления (VIEW)

Создадим обновляемое представление с помощью правил:

```sql
-- Создаем основную таблицу
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(50),
    salary DECIMAL(10,2)
);

INSERT INTO employees (name, department, salary) VALUES
('Иванов Иван Иванович', 'Бухгалтерия', 85000.50),
('Петрова Анна Сергеевна', 'Маркетинг', 92000.00),
('Сидоров Алексей Владимирович', 'IT-отдел', 125000.75),
('Кузнецова Елена Дмитриевна', 'Маркетинг', 78000.00),
('Федорова Мария Петровна', 'Бухгалтерия', 87000.50),
('Николаев Андрей Игоревич', 'IT-отдел', 135000.00);

-- Создаем представление только для определенного отдела
CREATE VIEW marketing_employees AS
SELECT id, name, salary FROM employees WHERE department = 'Маркетинг';

-- Создаем правила для поддержки операций INSERT/UPDATE/DELETE через представление
CREATE RULE insert_marketing AS ON INSERT TO marketing_employees DO INSTEAD
INSERT INTO employees (name, department, salary) VALUES (NEW.name, 'Marketing', NEW.salary);

CREATE RULE update_marketing AS ON UPDATE TO marketing_employees DO INSTEAD
UPDATE employees SET name = NEW.name, salary = NEW.salary 
WHERE id = OLD.id AND department = 'Маркетинг';

CREATE RULE delete_marketing AS ON DELETE TO marketing_employees DO INSTEAD
DELETE FROM employees WHERE id = OLD.id AND department = 'Маркетинг';
```

Теперь можно работать с представлением как с обычной таблицей:
```sql
INSERT INTO marketing_employees (name, salary) VALUES ('Джон Бидон', 50000);
UPDATE marketing_employees SET salary = 55000 WHERE name = 'Джон Бидон';
DELETE FROM marketing_employees WHERE name = 'Джон Бидон';
```

## Важные замечания о RULE:

1. Правила выполняются на этапе перезаписи запроса, а не во время его выполнения
2. Правила могут значительно усложнить понимание поведения базы данных
3. В большинстве случаев триггеры (TRIGGER) предпочтительнее правил
4. Правила применяются до оптимизации запроса

Правила - мощный, но редко используемый инструмент PostgreSQL, который может быть полезен в специфических сценариях.


## 🧱 Когда использовать правила?

### ✔ Подходит:

* Для создания **"умных" представлений**, которые поддерживают `INSERT`, `UPDATE`, `DELETE`.
* Когда нужно **перенаправить запрос** к другой таблице.
* Для **историзации** или **автоматического логирования**.

### ❌ Не рекомендуется:

* Для сложной логики, где лучше подходят **триггеры**.
* Когда нужна **последовательная обработка** (например, AFTER триггеры).
* Если важен **контроль порядка исполнения** — правила могут быть менее предсказуемы.

---

## 📚 Заключение

Правила — мощный, но устаревающий механизм. В большинстве случаев сейчас **предпочтительнее использовать триггеры**, особенно если нужна реакция на изменения данных.

Тем не менее, **для расширения поведения представлений** правила остаются единственным способом сделать `VIEW` «обновляемым» без использования `INSTEAD OF` триггеров (которые PostgreSQL пока не поддерживает напрямую).

Ниже — пример «умного» представления в PostgreSQL с поддержкой `SELECT`, `INSERT`, `UPDATE` и `DELETE` через **правила (`RULE`)**, которые делают представление *почти как таблицу*.

---

## 🧩 Задача

Допустим, у нас есть таблица с заказами:

```sql
CREATE TABLE orders (
  id serial PRIMARY KEY,
  customer text,
  amount numeric,
  is_public boolean DEFAULT false
);
```

Теперь мы хотим предоставить доступ к **только публичным заказам** другим пользователям через представление `public_orders`, но при этом позволить:

* читать публичные заказы (`SELECT`)
* добавлять новые только как публичные (`INSERT`)
* редактировать только публичные заказы (`UPDATE`)
* удалять только публичные заказы (`DELETE`)

---

## 🛠 Создание представления

```sql
CREATE VIEW public_orders AS
SELECT id, customer, amount
FROM orders
WHERE is_public = true;
```

---

## 🔁 Добавляем правила

### INSERT

```sql
CREATE RULE public_orders_insert AS
ON INSERT TO public_orders
DO INSTEAD
INSERT INTO orders (customer, amount, is_public)
VALUES (NEW.customer, NEW.amount, true);
```

> Любая вставка через `public_orders` автоматически будет `is_public = true`.

---

### UPDATE

```sql
CREATE RULE public_orders_update AS
ON UPDATE TO public_orders
DO INSTEAD
UPDATE orders
SET customer = NEW.customer,
    amount = NEW.amount
WHERE id = OLD.id AND is_public = true;
```

---

### DELETE

```sql
CREATE RULE public_orders_delete AS
ON DELETE TO public_orders
DO INSTEAD
DELETE FROM orders
WHERE id = OLD.id AND is_public = true;
```

---

## ✅ Проверка

```sql
-- Добавим данные через представление:
INSERT INTO public_orders (customer, amount) VALUES ('Alice', 100);

-- Посмотрим содержимое:
SELECT * FROM public_orders;
-- => Вывод: id | customer | amount

-- Обновим заказ:
UPDATE public_orders SET amount = 120 WHERE customer = 'Alice';

-- Удалим заказ:
DELETE FROM public_orders WHERE customer = 'Alice';
```

---

## 💡 Что происходит под капотом?

PostgreSQL, при обращении к `public_orders`, не выполняет действия напрямую с представлением. Вместо этого, благодаря `RULE`, он:

* переписывает запрос на `INSERT`, `UPDATE`, `DELETE` к таблице `orders`
* ограничивает действия только на `is_public = true`

---

## ⚠️ Ограничения

* Нет поддержки `RETURNING` с правилами.
* Не работает с `BEFORE/AFTER` логикой — если она нужна, лучше использовать триггеры на таблице.
* Если правило сработало, **исходный запрос не выполняется** (если есть `INSTEAD`).

---

## 📚 Заключение

Такой «умный» view через правила позволяет:

* Ограничить доступ к части данных
* Позволить управлять ими безопасно
* Работать с представлением как с обычной таблицей

