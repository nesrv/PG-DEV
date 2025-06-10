#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

start_here 5

###############################################################################
h 'Объявление и открытие'

c 'Создадим таблицу:'

s 1 "CREATE TABLE t(id integer, s text);"
s 1 "INSERT INTO t VALUES (1, 'Раз'), (2, 'Два'), (3, 'Три');"

c 'Несвязанная переменная:'

s 1 "DO \$\$
DECLARE
    -- объявление переменной
    cur refcursor; 
BEGIN
    -- связывание с запросом и открытие курсора
    OPEN cur FOR SELECT * FROM t;
END
\$\$;"

c 'Связанная переменная: запрос указывается уже при объявлении. При этом переменная cur имеет тот же тип refcursor.'

s 1 "DO \$\$
DECLARE
    -- объявление и связывание переменной
    cur CURSOR FOR SELECT * FROM t;
BEGIN
    -- открытие курсора
    OPEN cur; 
END
\$\$;"

c 'В случае связанной переменной запрос может иметь параметры.'
c 'Обратите внимание на устранение неоднозначности имен в этом и следующем примерах.'

s 1 "DO \$\$
DECLARE
    -- объявление и связывание переменной
    cur CURSOR(id integer) FOR SELECT * FROM t WHERE t.id = cur.id;
BEGIN
    -- открытие курсора с указанием фактических параметров
    OPEN cur(1);
END
\$\$;"

c 'Переменные PL/pgSQL также являются (неявными) параметрами курсора.'

s 1 "DO \$\$
<<local>>
DECLARE
    id integer := 3;
    -- объявление и связывание переменной
    cur CURSOR FOR SELECT * FROM t WHERE t.id = local.id;
BEGIN
    id := 1;
    -- открытие курсора (значение id берется на этот момент)
    OPEN cur;
END
\$\$;"

c 'В качестве запроса можно использовать не только команду SELECT, но и любую другую, возвращающую результат (например, INSERT, UPDATE, DELETE с фразой RETURNING).'

P 7

###############################################################################
h 'Операции с курсором'

c 'Чтение текущей строки из курсора выполняется командой FETCH. Если нужно только переместиться на следующую строку, можно воспользоваться другой командой — MOVE.'
c 'Что будет выведено на экран?'

s 1 "DO \$\$
DECLARE
    cur refcursor;
    rec record; -- можно использовать и несколько скалярных переменных
BEGIN
    OPEN cur FOR SELECT * FROM t ORDER BY id;
    MOVE cur;
    FETCH cur INTO rec;
    RAISE NOTICE '%', rec;
    CLOSE cur;
END
\$\$;"

c 'Обычно выборка происходит в цикле, который можно организовать так:'

s 1 "DO \$\$
DECLARE
    cur refcursor;
    rec record;
BEGIN
    OPEN cur FOR SELECT * FROM t;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND; -- FOUND: выбрана ли очередная строка?
        RAISE NOTICE '%', rec;
    END LOOP;
    CLOSE cur;
END
\$\$;"

c 'Но чтобы не писать много команд, в PL/pgSQL имеется цикл FOR по курсору, который делает ровно то же самое:'

s 1 "DO \$\$
DECLARE
    cur CURSOR FOR SELECT * FROM t;
    -- переменная цикла не объявляется
BEGIN
    FOR rec IN cur LOOP -- cur должна быть связана с запросом
        RAISE NOTICE '%', rec;
    END LOOP;
END
\$\$;"

c 'Более того, можно вообще обойтись без явной работы с курсором, если цикл — это все, что требуется.'
c 'Скобки вокруг запроса не обязательны, но удобны.'

s 1 "DO \$\$
DECLARE
    rec record; -- надо объявить явно
BEGIN
    FOR rec IN (SELECT * FROM t) LOOP
        RAISE NOTICE '%', rec;
    END LOOP;
END
\$\$;"

c 'Как и для любого цикла, здесь можно указать метку, что может оказаться полезным во вложенных циклах:'
c 'Что будет выведено?'

s 1 "DO \$\$
DECLARE
    rec_outer record;
    rec_inner record;
BEGIN
    <<outer>>
    FOR rec_outer IN (SELECT * FROM t ORDER BY id) LOOP
        <<inner>>
        FOR rec_inner IN (SELECT * FROM t ORDER BY id) LOOP
            EXIT outer WHEN rec_inner.id = 3;
            RAISE NOTICE '%, %', rec_outer, rec_inner;
        END LOOP INNER;
    END LOOP outer;
END
\$\$;"

c 'После выполнения цикла переменная FOUND позволяет узнать, была ли обработана хотя бы одна строка:'

s 1 "DO \$\$
DECLARE
    rec record;
BEGIN
    FOR rec IN (SELECT * FROM t WHERE false) LOOP
        RAISE NOTICE '%', rec;
    END LOOP;
    RAISE NOTICE 'Была ли как минимум одна итерация? %', FOUND;
END
\$\$;"

c 'На текущую строку курсора, связанного с простым запросом (по одной таблице, без группировок и сортировок) можно сослаться с помощью предложения CURRENT OF. Типичный случай применения — обработка пакета заданий с изменением статуса каждого из них.'

s 1 "DO \$\$
DECLARE
    cur refcursor;
    rec record;
BEGIN
    OPEN cur FOR SELECT * FROM t
        FOR UPDATE; -- строки блокируются по мере обработки
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        UPDATE t SET s = s || ' (обработано)' WHERE CURRENT OF cur;
    END LOOP;
    CLOSE cur;
END
\$\$;"

s 1 "SELECT * FROM t;"

c 'Заметим, что CURRENT OF не работает с циклом FOR по запросу, поскольку этот цикл не использует курсор явным образом. Конечно, аналогичный результат можно получить, явно указав в команде UPDATE или DELETE уникальный ключ таблицы (WHERE id = rec.id). Но CURRENT OF работает быстрее и не требует наличия индекса.'

p

c 'Следует заметить, что в большом числе случаев вместо использования циклов можно выполнить задачу одним оператором SQL — и это будет проще и еще быстрее. Часто циклы используют просто потому, что это более привычный, «процедурный» стиль программирования. Но для баз данных этот стиль не подходит.'
c 'Например:'

s 1 "BEGIN;
DO \$\$
DECLARE
    rec record;
BEGIN
    FOR rec IN (SELECT * FROM t) LOOP
        RAISE NOTICE '%', rec;
        DELETE FROM t WHERE id = rec.id;
    END LOOP;
END
\$\$;
ROLLBACK;"

c 'Такой цикл заменяется одной простой SQL-командой:'

s 1 "BEGIN;
DELETE FROM t RETURNING *;
ROLLBACK;"

P 9

###############################################################################
h 'Передача курсора клиенту'

c 'Откроем курсор и выведем значение курсорной переменной:'

s 1 "DO \$\$
DECLARE
    cur refcursor;
BEGIN
    OPEN cur FOR SELECT * FROM t;
    RAISE NOTICE '%', cur;
END
\$\$;"

c 'Это имя курсора (портала), который был открыт на сервере. Оно было сгенерировано автоматически.'

c 'При желании имя можно задать явно (но оно должно быть уникальным в сеансе):'

s 1 "DO \$\$
DECLARE
    cur refcursor := 'cursor12345';
BEGIN
    OPEN cur FOR SELECT * FROM t;
    RAISE NOTICE '%', cur;
END
\$\$;"

c 'Пользуясь этим, можно написать функцию, которая откроет курсор и вернет его имя:'

s 1 "CREATE FUNCTION t_cur() RETURNS refcursor 
AS \$\$
DECLARE
    cur refcursor;
BEGIN
    OPEN cur FOR SELECT * FROM t;
    RETURN cur;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Клиент начинает транзакцию...'
s 1 "BEGIN;"

c '...вызывает функцию, узнает имя курсора...'

# непонятно
#separator "sql" 1

s 1 "SELECT t_cur();"
curname=`echo $RESULT | head -n 3 | tail -n 1 | xargs`

c '...и получает возможность читать из него данные (кавычки нужны из-за спецсимволов в имени):'
s 1 "FETCH \"$curname\";"
s 1 "COMMIT;"

c 'Для удобства можно позволить клиенту самому устанавливать имя курсора:'

s 1 "DROP FUNCTION t_cur();"
s 1 "CREATE FUNCTION t_cur(cur refcursor) RETURNS void 
AS \$\$
BEGIN
    OPEN cur FOR SELECT * FROM t;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Клиентский код упрощается:'

s 1 "BEGIN;"
s 1 "SELECT t_cur('cursor12345');"
s 1 "FETCH cursor12345;"
s 1 "COMMIT;"

c 'Функция может вернуть и несколько открытых курсоров, используя OUT-параметры. Таким образом можно за один вызов функции обеспечить клиента информацией из разных таблиц, если это необходимо.'
c 'Альтернативный подход — сразу выбрать все необходимые данные на стороне сервера и сформировать из них документ JSON или XML. Работа с этими форматами рассматривается в курсе DEV2.'

###############################################################################

stop_here
cleanup
demo_end
