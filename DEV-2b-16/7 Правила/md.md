# Правила RULES


В PostgreSQL **правила (rules)** — это механизм, позволяющий **трансформировать SQL-запросы** перед их выполнением. Это часть **системы переписывания запросов**, которая позволяет подменять одни запросы другими, модифицировать их или выполнять дополнительные действия при обращении к таблице или представлению.

---

## 📘 Что такое правило в PostgreSQL?

Правило (`RULE`) — это **альтернатива триггерам**, которая позволяет описывать, как именно должен быть переписан SQL-запрос (например, `SELECT`, `INSERT`, `UPDATE`, `DELETE`) при обращении к определённой таблице или представлению.

---

## 🛠 Синтаксис создания правила

```sql
CREATE RULE имя_правила AS
ON операция
TO имя_таблицы_или_представления
[WHERE условие]
DO [INSTEAD] 
    действие;
```

### Пояснение:

* **операция** — `SELECT`, `INSERT`, `UPDATE`, `DELETE`
* **INSTEAD** — означает, что **исходный запрос будет заменён** указанным действием (аналог триггера `BEFORE`)
* **действие** — может быть SQL-запрос или `NOTHING`

---

## ✅ Пример 1: SELECT вместо доступа к представлению

Допустим, у нас есть представление:

```sql
CREATE VIEW public_orders AS
SELECT id, product, price FROM orders WHERE is_public = true;
```

И мы хотим разрешить выборку, но запретить изменение данных через это представление. Тогда:

```sql
CREATE RULE no_update AS
ON UPDATE TO public_orders
DO INSTEAD NOTHING;
```

Теперь любые попытки изменить данные через `public_orders` будут игнорироваться.

---

## ✅ Пример 2: INSERT преобразуется в вставку в другую таблицу

Допустим, у нас есть логгируемая таблица:

```sql
CREATE TABLE log_table (
  id serial,
  message text,
  created_at timestamp default now()
);
```

Создадим правило для вставки через представление:

```sql
CREATE VIEW log_view AS
SELECT id, message FROM log_table;
```

И правило:

```sql
CREATE RULE insert_log AS
ON INSERT TO log_view
DO INSTEAD
INSERT INTO log_table(message) VALUES (NEW.message);
```

Теперь `INSERT INTO log_view` на самом деле вставит данные в `log_table`.

---

## 🧠 Особенности

* Правила применяются **во время планирования запроса**, а не в момент его выполнения.
* Можно иметь **несколько правил** на одну и ту же операцию.
* PostgreSQL автоматически **разворачивает** правила в подзапросы — это может повлиять на производительность и читаемость плана.
* **INSTEAD** может быть **обязательным**, например, для `INSERT` в `VIEW`.

---

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

