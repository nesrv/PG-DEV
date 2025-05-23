
### **Обзор структуры (Блоков) PL/pgSQL в PostgreSQL**

**PL/pgSQL** — это процедурный язык, встроенный в PostgreSQL, который используется для создания хранимых процедур, функций, триггеров и для выполнения логики на сервере базы данных. Он расширяет возможности стандартного SQL, позволяя писать сложные алгоритмы и использовать переменные, условные операторы, циклы и другие конструкции программирования.

Программы на **PL/pgSQL** состоят из **блоков**, которые описывают, как выполняются операции в базе данных.

---

### 1. **Общая структура блока PL/pgSQL**

Структура программы в PL/pgSQL, как правило, делится на несколько частей. Блоки PL/pgSQL могут быть оформлены как **функции** или **процедуры**, и основная структура включает следующие компоненты:

1. **Заголовок**
2. **Объявление переменных**
3. **Основная логика**
4. **Возврат значения** (для функций)
5. **Обработка ошибок**

Вот пример базовой структуры блока PL/pgSQL:

```sql
CREATE OR REPLACE FUNCTION function_name() RETURNS return_type AS $$
DECLARE
    -- Объявление переменных
    var_name1 data_type;
    var_name2 data_type := initial_value;
BEGIN
    -- Основная логика
    -- Запросы, условные операторы, циклы, вызовы функций
    IF some_condition THEN
        -- Логика при условии
    ELSE
        -- Логика в противном случае
    END IF;

    -- Возврат значения (для функций)
    RETURN some_value;
EXCEPTION
    -- Обработка ошибок
    WHEN others THEN
        -- Логика обработки ошибок
        RAISE NOTICE 'An error occurred';
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

---

### 2. **Описание блоков PL/pgSQL**

#### **1. Заголовок**

Заголовок начинается с команды `CREATE FUNCTION` (или `CREATE PROCEDURE` для процедуры), где указывается имя функции/процедуры, возвращаемый тип данных (для функции), параметры и язык, в котором написана программа (`plpgsql`).

Пример:

```sql
CREATE OR REPLACE FUNCTION update_employee_salary(
    emp_id INT, 
    new_salary NUMERIC
) RETURNS VOID AS $$
```

Здесь:

* `update_employee_salary` — имя функции.
* `(emp_id INT, new_salary NUMERIC)` — параметры, которые принимает функция.
* `RETURNS VOID` — функция не возвращает значения (процедура).

#### **2. Объявление переменных**

Блок `DECLARE` используется для объявления переменных, которые будут использоваться в основной части блока.

Пример:

```sql
DECLARE
    current_salary NUMERIC;
```

Переменная `current_salary` будет использоваться для хранения текущей зарплаты сотрудника.

#### **3. Основная логика**

Основная логика помещается в блок `BEGIN...END`. Здесь пишутся SQL-запросы, операторы управления потоком (условия и циклы), а также другие конструкции.

Пример:

```sql
BEGIN
    -- Получение текущей зарплаты сотрудника
    SELECT salary INTO current_salary FROM employees WHERE id = emp_id;
    
    -- Условие для обновления зарплаты
    IF current_salary < new_salary THEN
        UPDATE employees SET salary = new_salary WHERE id = emp_id;
    ELSE
        RAISE NOTICE 'New salary must be greater than current salary';
    END IF;
END;
```

Здесь:

* Выполняется запрос для получения текущей зарплаты.
* Если новая зарплата больше текущей, выполняется обновление.
* В противном случае выводится сообщение о том, что новая зарплата должна быть больше.

#### **4. Возврат значения (для функции)**

Если блок является функцией, то в конце нужно использовать оператор `RETURN` для возврата значения.

Пример для функции, которая возвращает значение:

```sql
RETURN current_salary;
```

Для процедур (которые не возвращают значения), возврат не требуется.

#### **5. Обработка ошибок (EXCEPTION)**

PL/pgSQL предоставляет механизм обработки ошибок через блок `EXCEPTION`. Он перехватывает ошибки, которые могут возникнуть во время выполнения, и позволяет управлять ими, например, выводить сообщения или логировать ошибки.

Пример:

```sql
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'An error occurred while updating salary';
        RETURN NULL;
```

Здесь:

* Если возникает любая ошибка, блок `EXCEPTION` перехватывает её, выводит сообщение и возвращает `NULL`.

---

### 3. **Типы блоков в PL/pgSQL**

#### **1. Функции**

Функции в PL/pgSQL — это блоки, которые могут возвращать значение и могут быть использованы в SQL-запросах.

Пример функции:

```sql
CREATE OR REPLACE FUNCTION get_employee_salary(emp_id INT) 
RETURNS NUMERIC AS $$
DECLARE
    emp_salary NUMERIC;
BEGIN
    SELECT salary INTO emp_salary FROM employees WHERE id = emp_id;
    RETURN emp_salary;
END;
$$ LANGUAGE plpgsql;
```

#### **2. Процедуры**

Процедуры, в отличие от функций, не возвращают значения. Они предназначены для выполнения операций на сервере базы данных, таких как изменения данных или выполнение транзакций.

Пример процедуры:

```sql
CREATE OR REPLACE PROCEDURE update_employee_salary(emp_id INT, new_salary NUMERIC) AS $$
BEGIN
    UPDATE employees SET salary = new_salary WHERE id = emp_id;
END;
$$ LANGUAGE plpgsql;
```

#### **3. Триггеры**

Триггеры — это блоки кода, которые автоматически выполняются при определённых событиях, таких как вставка, обновление или удаление строк в таблице. Триггеры могут быть написаны на PL/pgSQL.

Пример триггера:

```sql
CREATE OR REPLACE FUNCTION log_employee_update() 
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO employee_audit (emp_id, action, action_time)
    VALUES (NEW.id, 'UPDATE', NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER employee_update_trigger
AFTER UPDATE ON employees
FOR EACH ROW EXECUTE FUNCTION log_employee_update();
```

---

### 4. **Основные операторы PL/pgSQL**

1. **Условные операторы**:

   * `IF ... THEN ... ELSE` — условные операторы.
   * `CASE` — альтернативный способ работы с условиями.

2. **Циклы**:

   * `LOOP` — базовый цикл.
   * `FOR` — цикл с итерациями.
   * `WHILE` — цикл с условием.

3. **Операторы**:

   * `RETURN` — для возврата значения (в функциях).
   * `RAISE` — для вывода сообщений или выброса ошибок.
   * `PERFORM` — для выполнения запросов, результат которых не важен.

---

### Заключение

PL/pgSQL предоставляет мощные средства для работы с логикой базы данных, включая переменные, циклы, условия и обработку ошибок. С помощью **функций**, **процедур** и **триггеров** можно автоматизировать процессы, повысить производительность и упростить поддержку базы данных.




### Процедуры (Procedure) в PostgreSQL

**Процедуры** в PostgreSQL — это объекты, которые содержат набор SQL-запросов и выполняют действия на сервере базы данных. В отличие от **функций**, процедуры не возвращают значения, но могут выполнять различные операции, такие как обновления данных, создание новых записей или выполнение других действий на сервере.

Процедуры были введены в PostgreSQL начиная с версии 11, и они предоставляют более гибкие возможности для работы с базой данных, чем функции, поскольку могут выполнять транзакции и не обязаны возвращать значение.

---

### 1. **Создание процедуры**

Процедуры создаются с использованием команды `CREATE PROCEDURE`, где необходимо указать имя процедуры, список параметров (если они есть) и сам код процедуры, который может содержать SQL-запросы, циклы и условные операторы.

Пример:

```sql
CREATE OR REPLACE PROCEDURE update_employee_salary(emp_id INT, new_salary NUMERIC) AS $$
BEGIN
    UPDATE employees SET salary = new_salary WHERE id = emp_id;
    RAISE NOTICE 'Salary updated for employee with ID %', emp_id;
END;
$$ LANGUAGE plpgsql;
```

* **Параметры**: `emp_id` и `new_salary` — параметры, которые передаются в процедуру.
* **Тело процедуры**: Здесь используется командой `UPDATE` для обновления зарплаты сотрудника. Также выводится сообщение через `RAISE NOTICE`.

### 2. **Удаление процедуры**

Для удаления процедуры используется команда `DROP PROCEDURE`. Важно, что при удалении процедуры необходимо точно указать количество и тип параметров, если они были определены.

Пример:

```sql
DROP PROCEDURE IF EXISTS update_employee_salary(INT, NUMERIC);
```

* Если процедура не существует, опция `IF EXISTS` предотвращает ошибку.

### 3. **Вызов процедуры**

Процедуры в PostgreSQL вызываются с помощью команды `CALL`. В отличие от функций, для вызова процедур не нужно использовать `SELECT`.

Пример:

```sql
CALL update_employee_salary(101, 75000);
```

Здесь:

* `101` — это значение параметра `emp_id`.
* `75000` — это значение параметра `new_salary`.

Процедура `update_employee_salary` будет выполнена для сотрудника с `id = 101` и установит ему новую зарплату `75000`.

### 4. **Просмотр информации о процедурах**

Для получения информации о созданных процедурах в базе данных можно использовать различные системные таблицы и представления, такие как `pg_catalog.pg_proc`, `pg_catalog.pg_namespace` и `pg_catalog.pg_language`.

#### Пример 1: Просмотр списка всех процедур в базе данных

```sql
SELECT proname, proargtypes, prosrc
FROM pg_catalog.pg_proc
WHERE pronamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'public')
  AND proisagg = false;
```

Здесь:

* `proname` — имя процедуры.
* `proargtypes` — типы аргументов.
* `prosrc` — исходный код процедуры.

#### Пример 2: Просмотр процедур с их параметрами

```sql
SELECT p.proname, p.proargtypes, p.prosrc, n.nspname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'p'; -- 'p' - для процедур
```

Этот запрос выводит имя процедур, их аргументы, исходный код и имя схемы, в которой они находятся.

#### Пример 3: Использование `pg_catalog.pg_proc` для поиска информации о процедурах по имени

```sql
SELECT * 
FROM pg_catalog.pg_proc 
WHERE proname = 'update_employee_salary';
```

Этот запрос покажет все процедуры с именем `update_employee_salary` в базе данных.

#### Пример 4: Просмотр всех объектов в схеме, включая функции и процедуры

```sql
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE specific_schema = 'public';
```

Этот запрос выводит все функции и процедуры в схеме `public`, их имена и типы (функции или процедуры).

---

### Заключение

Процедуры в PostgreSQL позволяют инкапсулировать логику на сервере базы данных и выполнять её без необходимости возвращать значения, что полезно для операций, которые не требуют возвращаемого результата, например, обновления или модификации данных.

* **Создание процедуры**: используется команда `CREATE PROCEDURE`.
* **Вызов процедуры**: выполняется с помощью команды `CALL`.
* **Удаление процедуры**: для этого используется команда `DROP PROCEDURE`.
* **Просмотр информации о процедурах**: можно использовать системные таблицы, такие как `pg_proc` и `information_schema.routines`.



### **Пакеты (Packages) в PostgreSQL**

В PostgreSQL нет прямой поддержки **пакетов** (как, например, в Oracle). Однако, вы можете организовать код с использованием **схем** и **множества связанных функций и процедур**, чтобы создавать структуру, аналогичную пакетам. В PostgreSQL вы можете группировать функции и процедуры в отдельные схемы и работать с ними как с логически связанными наборами.

Однако для организации и работы с группами функций и процедур часто используется **множество функций и процедур в одной схеме** или **модули** (расширения), что позволяет структурировать код.

### Как сымитировать концепцию пакетов в PostgreSQL

1. **Создание схемы (Schema)**: можно создать схему, которая будет служить "пакетом".
2. **Создание функций и процедур в этой схеме**: функции и процедуры, относящиеся к пакету, можно хранить в этой схеме.
3. **Вызов функций из этой схемы**: для вызова функций из схемы необходимо указать имя схемы перед именем функции.

---

### 1. **Создание схемы для пакета**

В PostgreSQL схема представляет собой контейнер для таблиц, функций и других объектов базы данных. Можно создать схему и использовать её как "пакет" для группировки функций и процедур.

Пример:

```sql
CREATE SCHEMA my_package;
```

Эта команда создаёт схему с именем `my_package`.

---

### 2. **Создание функций и процедур в пакете (схеме)**

Теперь вы можете создавать функции и процедуры в созданной схеме, используя синтаксис, аналогичный созданию обычных функций, но с указанием схемы в имени.

#### Пример 1: Создание функции в схеме

```sql
CREATE OR REPLACE FUNCTION my_package.get_employee_salary(emp_id INT)
RETURNS NUMERIC AS $$
DECLARE
    emp_salary NUMERIC;
BEGIN
    SELECT salary INTO emp_salary FROM employees WHERE id = emp_id;
    RETURN emp_salary;
END;
$$ LANGUAGE plpgsql;
```

* Функция `get_employee_salary` будет находиться в схеме `my_package`.
* Для вызова этой функции необходимо будет указывать полное имя: `my_package.get_employee_salary`.

#### Пример 2: Создание процедуры в схеме

```sql
CREATE OR REPLACE PROCEDURE my_package.update_employee_salary(emp_id INT, new_salary NUMERIC) AS $$
BEGIN
    UPDATE employees SET salary = new_salary WHERE id = emp_id;
    RAISE NOTICE 'Salary updated for employee with ID %', emp_id;
END;
$$ LANGUAGE plpgsql;
```

* Процедура `update_employee_salary` также будет находиться в схеме `my_package`.

---

### 3. **Вызов функций и процедур из пакета**

Для вызова функций и процедур из схемы нужно использовать имя схемы перед именем функции или процедуры.

#### Пример 1: Вызов функции из пакета

```sql
SELECT my_package.get_employee_salary(101);
```

* В этом примере функция `get_employee_salary` вызывается из схемы `my_package` для получения зарплаты сотрудника с `id = 101`.

#### Пример 2: Вызов процедуры из пакета

```sql
CALL my_package.update_employee_salary(101, 75000);
```

* Процедура `update_employee_salary` вызывается для обновления зарплаты сотрудника с `id = 101` на `75000`.

---

### 4. **Удаление функций и процедур из пакета**

Для удаления функций или процедур в PostgreSQL используется команда `DROP FUNCTION` или `DROP PROCEDURE`.

Пример:

```sql
DROP FUNCTION IF EXISTS my_package.get_employee_salary(INT);
DROP PROCEDURE IF EXISTS my_package.update_employee_salary(INT, NUMERIC);
```

* При удалении функции или процедуры нужно точно указать типы аргументов, если они есть.

---

### 5. **Просмотр информации о функциях и процедурах в пакете**

Чтобы увидеть функции и процедуры, созданные в конкретной схеме (пакете), можно использовать системные представления, такие как `pg_catalog.pg_proc` и `pg_catalog.pg_namespace`.

#### Пример 1: Просмотр всех функций в схеме

```sql
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE specific_schema = 'my_package';
```

Этот запрос покажет все функции и процедуры в схеме `my_package`. `routine_name` — имя функции или процедуры, а `routine_type` — тип (функция или процедура).

#### Пример 2: Просмотр всех функций и процедур с их параметрами

```sql
SELECT p.proname, p.proargtypes, n.nspname
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'my_package';
```

Этот запрос выводит все функции и процедуры в схеме `my_package` с указанием типов аргументов и схемы.

---

### 6. **Просмотр всех функций в базе данных**

Если нужно увидеть все функции и процедуры, включая те, что находятся в схемах, можно использовать запрос к представлению `information_schema.routines`.

Пример:

```sql
SELECT routine_name, routine_type, specific_schema
FROM information_schema.routines;
```

Этот запрос покажет все функции и процедуры в базе данных, а также информацию о том, в какой схеме они находятся.

---

### Заключение

В PostgreSQL нет прямой поддержки **пакетов** как в Oracle, но можно использовать схемы для группировки связанных процедур и функций. С помощью схем можно организовать код, создавая структуру, аналогичную пакетам.

* **Создание схемы**: используйте команду `CREATE SCHEMA` для создания контейнера для функций и процедур.
* **Создание функций и процедур**: используйте команду `CREATE FUNCTION` или `CREATE PROCEDURE`, указав схему.
* **Вызов функций и процедур**: для вызова используйте `CALL` для процедур и `SELECT` для функций с указанием имени схемы.
* **Удаление функций и процедур**: используйте команду `DROP FUNCTION` или `DROP PROCEDURE`.
* **Просмотр информации**: используйте системные представления, такие как `information_schema.routines` и `pg_catalog.pg_proc`.



## Шпаргалка по PL/pgSQL

### Базовые конструкции

**Создание функции:**
```sql
CREATE OR REPLACE FUNCTION function_name([parameters])
RETURNS return_type AS $$
DECLARE
    -- объявление переменных
BEGIN
    -- код функции
    RETURN значение;
END;
$$ LANGUAGE plpgsql;
```

### Переменные и типы данных

**Объявление переменных:**
```sql
DECLARE
    var_name1 type1 := значение;
    var_name2 type2;
    rec_name RECORD;
    row_name table_name%ROWTYPE;
```

### Условные операторы

**IF-ELSE:**
```sql
IF условие THEN
    -- код
ELSIF условие THEN
    -- код
ELSE
    -- код
END IF;
```

**CASE:**
```sql
CASE выражение
    WHEN значение1 THEN результат1
    WHEN значение2 THEN результат2
    ELSE результат_по_умолчанию
END CASE;
```

### Циклы

**FOR:**
```sql
FOR i IN 1..10 LOOP
    -- код
END LOOP;
```

**WHILE:**
```sql
WHILE условие LOOP
    -- код
END LOOP;
```

### Обработка ошибок

**EXCEPTION:**
```sql
BEGIN
    -- код
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- обработка ошибки
    WHEN OTHERS THEN
        -- обработка всех остальных ошибок
END;
```

### Работа с курсорами

**Создание курсора:**
```sql
DECLARE
    cursor_name CURSOR FOR
        SELECT запрос;

OPEN cursor_name;
FETCH cursor_name INTO переменная;
CLOSE cursor_name;
```

### Возврат данных

**Возврат скалярного значения:**
```sql
CREATE FUNCTION get_value()
RETURNS integer AS $$
BEGIN
    RETURN 42;
END;
$$ LANGUAGE plpgsql;
```

**Возврат набора данных:**
```sql
CREATE FUNCTION get_rows()
RETURNS SETOF table_name AS $$
BEGIN
    RETURN QUERY SELECT * FROM table_name;
END;
$$ LANGUAGE plpgsql;
```

### Триггеры

**Создание триггера:**
```sql
CREATE TRIGGER trigger_name
BEFORE INSERT ON table_name
FOR EACH ROW
EXECUTE FUNCTION trigger_function();
```

### Полезные операторы

**Динамический SQL:**
```sql
EXECUTE 'SELECT * FROM ' || quote_ident(table_name);
```

**Работа с массивами:**
```sql
DECLARE
    arr integer[];
BEGIN
    arr := ARRAY[1, 2, 3];
    FOR i IN array_lower(arr, 1)..array_upper(arr, 1) LOOP
        -- код
    END LOOP;
END;
```

### Важные рекомендации

* Всегда используйте `DECLARE` для объявления переменных
* Обрабатывайте ошибки через блок `EXCEPTION`
* Используйте `RAISE NOTICE` для отладки
* Применяйте `PERFORM` для выполнения запросов без возврата результата
* Используйте `SETOF` для возврата множественных значений

### Типичные ошибки

* Неправильное использование кавычек в динамическом SQL
* Отсутствие обработки ошибок
* Неправильная работа с типами данных
* Использование `SELECT INTO` без проверки результата
* Отсутствие проверки на `NULL` значения