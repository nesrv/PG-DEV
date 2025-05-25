### 🔌 Расширение `lo` в PostgreSQL

Расширение `lo` добавляет удобные SQL-обёртки над низкоуровневыми функциями для работы с **большими объектами** (`Large Objects`) в PostgreSQL. Оно позволяет легко использовать такие функции, как `lo_create`, `lo_import`, `lo_export`, `lo_open`, `lowrite`, `loread`, и другие.

---

### 📦 Как установить расширение `lo`

```sql
CREATE EXTENSION lo;
```

> ⚠️ Обычно это делается один раз на базу данных. Требуются суперправа или роль `CREATEDB`.

---

### 📋 Что добавляет `lo`

* Таблица системных больших объектов:
  **`pg_largeobject`** — сами данные
  **`pg_largeobject_metadata`** — метаданные (OID, разрешения и пр.)

* Обёртки:

  | Функция                | Описание                           |
  | ---------------------- | ---------------------------------- |
  | `lo_create(oid)`       | Создание большого объекта          |
  | `lo_unlink(oid)`       | Удаление большого объекта          |
  | `lo_import(path)`      | Импорт файла в БД как LOB          |
  | `lo_export(oid, path)` | Экспорт большого объекта в файл    |
  | `lo_open(oid, mode)`   | Открытие объекта для чтения/записи |
  | `lowrite(fd, bytea)`   | Запись байт в объект               |
  | `loread(fd, size)`     | Чтение байт из объекта             |
  | `lo_close(fd)`         | Закрытие объекта                   |

---

### 📂 Пример использования `lo_import` / `lo_export`

```sql
-- Импорт файла в базу
SELECT lo_import('/tmp/sample.pdf');

-- Экспорт объекта (например, с OID 12345)
SELECT lo_export(12345, '/tmp/out.pdf');
```

---

### 🔒 Управление правами

Можно использовать `GRANT`/`REVOKE` на уровне таблицы `pg_largeobject_metadata`, чтобы управлять доступом к LOB'ам.

---

### 📌 Где используется

* Хранение больших бинарных данных: PDF, изображения, видео и т.п.
* Удобен, когда объём данных превышает лимиты `TOAST` (\~1 ГБ).

---



# Пример использования `lo_import` / `lo_export`

Вот пример на **PL/pgSQL**, который показывает, как использовать расширение `lo` для загрузки, чтения и удаления большого объекта (LOB):

---

### ✅ Условие

* Предположим, у вас есть файл `/tmp/test_file.txt`, который нужно загрузить в базу как большой объект, прочитать его содержимое, а затем удалить.
* Расширение `lo` уже создано:

  ```sql
  CREATE EXTENSION IF NOT EXISTS lo;
  ```

---

### 📄 Пример PL/pgSQL-функции

```sql
DO $$
DECLARE
    lob_oid OID;
    lob_fd INTEGER;
    data BYTEA;
BEGIN
    -- Импорт файла в базу как большой объект
    lob_oid := lo_import('/tmp/test_file.txt');
    RAISE NOTICE 'LOB OID = %', lob_oid;

    -- Открываем LOB для чтения
    lob_fd := lo_open(lob_oid, 262144);  -- 262144 = INV_READ
    RAISE NOTICE 'LOB FD = %', lob_fd;

    -- Читаем 1 КБ данных
    data := loread(lob_fd, 1024);
    RAISE NOTICE 'Data (truncated) = %', convert_from(data, 'UTF8');

    -- Закрываем дескриптор
    PERFORM lo_close(lob_fd);

    -- Удаляем LOB из базы
    PERFORM lo_unlink(lob_oid);
    RAISE NOTICE 'LOB % deleted', lob_oid;
END;
$$ LANGUAGE plpgsql;
```

---

### 🧠 Что происходит

| Шаг         | Описание                            |
| ----------- | ----------------------------------- |
| `lo_import` | Загружает файл и возвращает его OID |
| `lo_open`   | Открывает LOB для чтения            |
| `loread`    | Читает данные из LOB                |
| `lo_close`  | Закрывает LOB                       |
| `lo_unlink` | Удаляет LOB из базы                 |

---

# pgAdmin with lo

Работа с большими объектами (`lo`, Large Objects) в **pgAdmin** немного ограничена по сравнению с программными средствами (например, через `psql`, `PL/pgSQL`, или библиотеки вроде `psycopg2`), но всё же возможна с использованием SQL-запросов в **Query Tool**.

---

## 🔧 Шаги: как работать с `lo` в pgAdmin

### 1. 📦 Установите расширение `lo` (один раз на базу)

```sql
CREATE EXTENSION IF NOT EXISTS lo;
```

---

### 2. 📥 Импорт файла в LOB

```sql
SELECT lo_import('/absolute/path/to/your/file.txt');
```

🔸 **Важно:** `lo_import` и `lo_export` работают **только в psql или с суперпользовательскими правами**, и **только на сервере**, где запущен PostgreSQL.
В **pgAdmin** этот путь должен быть **на сервере**, не на вашем клиенте.

Если вы работаете из **pgAdmin на удалённой машине**, то файл должен быть на **сервере PostgreSQL**, не на вашем компьютере.

---

### 3. 🧾 Чтение содержимого LOB

Чтобы прочитать LOB, используйте `lo_open`, `loread` и т. д., как в PL/pgSQL:

```sql
DO $$
DECLARE
    fd integer;
    oid oid := 123456;  -- замените на свой OID
    data bytea;
BEGIN
    fd := lo_open(oid, 262144); -- INV_READ
    data := loread(fd, 4096);
    RAISE NOTICE 'Data: %', convert_from(data, 'UTF8');
    PERFORM lo_close(fd);
END;
$$ LANGUAGE plpgsql;
```

---

### 4. 🗑️ Удаление LOB

```sql
SELECT lo_unlink(123456);  -- замените на свой OID
```

---

## 🧠 Как узнать список LOB

```sql
SELECT loid, pg_size_pretty(length(data)) 
FROM pg_largeobject_metadata m
JOIN pg_largeobject l ON l.loid = m.oid
LIMIT 10;
```

---

## 💡 Советы

| Что                                               | Как                                                                                                                   |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| 📍 Где хранятся LOB?                              | В системной таблице `pg_largeobject`                                                                                  |
| 🔐 Кто может работать с lo\_import/lo\_export?    | Только суперпользователь                                                                                              |
| 🔄 Как использовать из клиента?                   | Лучше использовать клиент `psql` или язык программирования (Python, Java и др.)                                       |
| 📁 Как загрузить файл с компьютера через pgAdmin? | Никак напрямую — pgAdmin не может "вытянуть" файл с вашей машины в LOB. Нужна серверная утилита (`psql`, скрипт, API) |

---




