#!/bin/bash

. ../lib

init_app
roll_to 17

start_here

###############################################################################
h '1. Триггер для обновления каталога'

s 1 "CREATE FUNCTION update_catalog() RETURNS trigger
AS \$\$
BEGIN
    INSERT INTO operations(book_id, qty_change) VALUES
        (OLD.book_id, NEW.onhand_qty - coalesce(OLD.onhand_qty,0));
    RETURN NEW;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

s 1 "CREATE TRIGGER update_catalog_trigger
INSTEAD OF UPDATE ON catalog_v
FOR EACH ROW
EXECUTE FUNCTION update_catalog();"

###############################################################################
h '2. Проверка количества книг'

c 'Добавляем к таблице книг поле наличного количества. (До версии 11 важно было учитывать, что указание предложения DEFAULT вызывало перезапись всех строк таблицы, удерживая блокировку.)'

s 1 "ALTER TABLE books ADD COLUMN onhand_qty integer;"

c 'Триггерная функция для AFTER-триггера на вставку для обновления количества (предполагаем, что поле onhand_qty не может быть пустым):'

s 1 "CREATE FUNCTION update_onhand_qty() RETURNS trigger
AS \$\$
BEGIN
    UPDATE books
    SET onhand_qty = onhand_qty + NEW.qty_change
    WHERE book_id = NEW.book_id;
    RETURN NULL;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Дальше все происходит внутри транзакции.'

s 1 "BEGIN;"

c 'Блокируем операции на время транзакции:'

s 1 "LOCK TABLE operations;"

c 'Начальное заполнение:'

s 1 "UPDATE books b
SET onhand_qty = (
    SELECT coalesce(sum(qty_change),0)
    FROM operations o
    WHERE o.book_id = b.book_id
);"

c 'Теперь, когда поле заполнено, задаем ограничения:'

s 1 "ALTER TABLE books ALTER COLUMN onhand_qty SET DEFAULT 0;"
s 1 "ALTER TABLE books ALTER COLUMN onhand_qty SET NOT NULL;"
s 1 "ALTER TABLE books ADD CHECK(onhand_qty >= 0);"

c 'Создаем триггер:'

s 1 "CREATE TRIGGER update_onhand_qty_trigger
AFTER INSERT ON operations
FOR EACH ROW
EXECUTE FUNCTION update_onhand_qty();"

c 'Готово.'

s 1 "COMMIT;"

c 'Теперь books.onhand_qty обновляется, но представление catalog_v по-прежнему вызывает функцию для подсчета количества. Хоть в исходном запросе обращение к функции синтаксически не отличается от обращения к полю, запрос был запомнен в другом виде:'

s 1 '\d+ catalog_v'

c 'Поэтому пересоздадим представление:'

s 1 "CREATE OR REPLACE VIEW catalog_v AS
SELECT b.book_id,
       b.title,
       b.onhand_qty,
       book_name(b.book_id, b.title) AS display_name,
       b.authors
FROM   books b
ORDER BY display_name;"

c 'Теперь функцию можно удалить.'

s 1 "DROP FUNCTION onhand_qty(books);"

c 'Небольшая проверка:'

s 1 "SELECT * FROM catalog_v WHERE book_id = 1 \gx"
s 1 "INSERT INTO operations(book_id, qty_change) VALUES (1,+10);"
s 1 "SELECT * FROM catalog_v WHERE book_id = 1 \gx"

c 'Некорректные операции обрываются:'

s 1 "INSERT INTO operations(book_id, qty_change) VALUES (1,-100);"

###############################################################################

stop_here
cleanup_app
