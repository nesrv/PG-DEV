#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Счетчик номера версии'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Таблица:'

s 1 'CREATE TABLE t(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    s text,
    version integer
);'

c 'Триггерная функция:'

s 1 "CREATE FUNCTION inc_version() RETURNS trigger
AS \$\$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.version := 1;
    ELSE
        NEW.version := OLD.version + 1;
    END IF;
    RETURN NEW;
END
\$\$ LANGUAGE plpgsql;"

c 'Триггер:'

s 1 'CREATE TRIGGER t_inc_version
BEFORE INSERT OR UPDATE ON t
FOR EACH ROW EXECUTE FUNCTION inc_version();'

c 'Проверяем:'

s 1 "INSERT INTO t(s) VALUES ('Раз');"
s 1 "SELECT * FROM t;"

c 'Явное указание version игнорируется:'

s 1 "INSERT INTO t(s,version) VALUES ('Два',42);"
s 1 "SELECT * FROM t;"

c 'Изменение:'

s 1 "UPDATE t SET s = lower(s) WHERE id = 1;"
s 1 "SELECT * FROM t;"

c 'Явное указание также игнорируется:'

s 1 "UPDATE t SET s = lower(s), version = 42 WHERE id = 2;"
s 1 "SELECT * FROM t;"

###############################################################################
h '2. Автоматическое вычисление общей суммы заказов'

c "Создаем таблицы упрощенной структуры, достаточной для демонстрации:"

s 1 "CREATE TABLE orders (
    id integer PRIMARY KEY,
    total_amount numeric(20,2) NOT NULL DEFAULT 0
);"


s 1 "CREATE TABLE lines (
   id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   order_id integer NOT NULL REFERENCES orders(id),
   amount numeric(20,2) NOT NULL
);"

c "Создаем триггерную функцию и триггер для обработки вставки:"

s 1 "CREATE FUNCTION total_amount_ins() RETURNS trigger
AS \$\$
BEGIN
    WITH l(order_id, total_amount) AS (
        SELECT order_id, sum(amount)
        FROM new_table
        GROUP BY order_id
    )
    UPDATE orders o
    SET total_amount = o.total_amount + l.total_amount
    FROM l
    WHERE o.id = l.order_id;
    RETURN NULL;
END
\$\$ LANGUAGE plpgsql;"

c 'Предложение FROM в команде UPDATE позволяет соединить orders с подзапросом по переходной таблице и использовать столбцы подзапроса для вычисления значения.'

s 1 "CREATE TRIGGER lines_total_amount_ins
AFTER INSERT ON lines
REFERENCING
    NEW TABLE AS new_table
FOR EACH STATEMENT
EXECUTE FUNCTION total_amount_ins();"

c 'Функция и триггер для обработки обновления:'

s 1 "CREATE FUNCTION total_amount_upd() RETURNS trigger
AS \$\$
BEGIN
    WITH l_tmp(order_id, amount) AS (
        SELECT order_id, amount FROM new_table
        UNION ALL
        SELECT order_id, -amount FROM old_table
    ), l(order_id, total_amount) AS (
        SELECT order_id, sum(amount)
        FROM l_tmp
        GROUP BY order_id
        HAVING sum(amount) <> 0
    )
    UPDATE orders o
    SET total_amount = o.total_amount + l.total_amount
    FROM l
    WHERE o.id = l.order_id;
    RETURN NULL;
END
\$\$ LANGUAGE plpgsql;"

c 'Условие HAVING позволяет пропускать изменения, не влияющие на общую сумму заказа.'

s 1 "CREATE TRIGGER lines_total_amount_upd
AFTER UPDATE ON lines
REFERENCING
    OLD TABLE AS old_table
    NEW TABLE AS new_table
FOR EACH STATEMENT
EXECUTE FUNCTION total_amount_upd();"

c 'Функция и триггер для обработки удаления:'

s 1 "CREATE FUNCTION total_amount_del() RETURNS trigger
AS \$\$
BEGIN
    WITH l(order_id, total_amount) AS (
        SELECT order_id, -sum(amount)
        FROM old_table
        GROUP BY order_id
    )
    UPDATE orders o
    SET total_amount = o.total_amount + l.total_amount
    FROM l
    WHERE o.id = l.order_id;
    RETURN NULL;
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE TRIGGER lines_total_amount_del
AFTER DELETE ON lines
REFERENCING
    OLD TABLE AS old_table
FOR EACH STATEMENT
EXECUTE FUNCTION total_amount_del();"

c "Остался неохваченным оператор TRUNCATE. Однако триггер для этого оператора не может использовать переходные таблицы. Но мы знаем, что после выполнения TRUNCATE в lines не останется строк, значит можно обнулить суммы всех заказов."

s 1 "CREATE FUNCTION total_amount_truncate() RETURNS trigger
AS \$\$
BEGIN
    UPDATE orders SET total_amount = 0;
    RETURN NULL;
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE TRIGGER lines_total_amount_truncate
AFTER TRUNCATE ON lines
FOR EACH STATEMENT
EXECUTE FUNCTION total_amount_truncate();"

c "Дополнительно нужно запретить изменять значение total_amount вручную, но это задача решается не триггерами."

c "Проверяем работу."

c "Добавили два новых заказа без строк:"
s 1 "INSERT INTO orders VALUES (1), (2);"
s 1 "SELECT * FROM orders ORDER BY id;"

c "Добавили строки в заказы:"
s 1 "INSERT INTO lines (order_id, amount) VALUES
    (1,100), (1,100), (2,500), (2,500);"
s 1 "SELECT * FROM lines;"
s 1 "SELECT * FROM orders ORDER BY id;"

c "Удвоили суммы всех строк всех заказов:"
s 1 "UPDATE lines SET amount = amount * 2;"
s 1 "SELECT * FROM orders ORDER BY id;"

c "Удалим одну строку первого заказа:"
s 1 "DELETE FROM lines WHERE id = 1;"
s 1 "SELECT * FROM orders ORDER BY id;"

c "Опустошим таблицу строк:"
s 1 "TRUNCATE lines;"
s 1 "SELECT * FROM orders ORDER BY id;"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
