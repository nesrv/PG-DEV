#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

start_here 10

###############################################################################
h 'Порядок вызова триггеров'

c 'Создадим «универсальную» триггерную функцию, которая описывает контекст, в котором она вызвана. Контекст передается в различных TG-переменных.'
c 'Затем создадим триггеры на различные события, и будем смотреть, какие триггеры и в каком порядке вызываются при выполнении операций.'

s 1 "CREATE OR REPLACE FUNCTION describe() RETURNS trigger
AS \$\$
DECLARE
    rec record;
    str text := '';
BEGIN
    IF TG_LEVEL = 'ROW' THEN
        CASE TG_OP
            WHEN 'DELETE' THEN rec := OLD; str := OLD::text;
            WHEN 'UPDATE' THEN rec := NEW; str := OLD || ' -> ' || NEW;
            WHEN 'INSERT' THEN rec := NEW; str := NEW::text;
        END CASE;
    END IF;
    RAISE NOTICE '% % % %: %',
        TG_TABLE_NAME, TG_WHEN, TG_OP, TG_LEVEL, str;
    RETURN rec;
END
\$\$ LANGUAGE plpgsql;"

c 'Таблица:'

s 1 'CREATE TABLE t(
    id integer PRIMARY KEY,
    s text
);'

c 'Триггеры на уровне оператора.'

s 1 'CREATE TRIGGER t_before_stmt
BEFORE INSERT OR UPDATE OR DELETE -- события
ON t                              -- таблица
FOR EACH STATEMENT                -- уровень
EXECUTE FUNCTION describe();      -- триггерная функция'
s 1 'CREATE TRIGGER t_after_stmt
AFTER INSERT OR UPDATE OR DELETE ON t
FOR EACH STATEMENT EXECUTE FUNCTION describe();'

c 'И на уровне строк:'

s 1 'CREATE TRIGGER t_before_row
BEFORE INSERT OR UPDATE OR DELETE ON t
FOR EACH ROW EXECUTE FUNCTION describe();'
s 1 'CREATE TRIGGER t_after_row
AFTER INSERT OR UPDATE OR DELETE ON t
FOR EACH ROW EXECUTE FUNCTION describe();'

c 'Пробуем вставку:'

s 1 "INSERT INTO t VALUES (1,'aaa'), (2, 'bbb');"

p

c 'Обновление:'

s 1 "UPDATE t SET s = 'ccc' WHERE id = 1;"

p

c 'Триггеры на уровне оператора сработают, даже если команда не обработала ни одной строки:'

s 1 "UPDATE t SET s = 'ddd' WHERE id = 0;"

p

c 'Тонкий момент: оператор INSERT с предложением ON CONFLICT приводит к тому, что срабатывают BEFORE-триггеры и на вставку, и на обновление:'

s 1 "INSERT INTO t VALUES (1,'ddd'), (3,'eee')
ON CONFLICT(id) DO UPDATE SET s = EXCLUDED.s;"

p

c 'И, наконец, удаление:'

s 1 "DELETE FROM t WHERE id = 2;"

p

c 'Для появившегося в PostgreSQL 15 оператора MERGE специального триггера нет, работают триггеры на обновление, удаление и вставку:'

s 1 "MERGE INTO t
USING (VALUES (1, 'fff'), (3, 'ggg'), (4, 'hhh')) AS vals(id, s)
ON t.id = vals.id
WHEN MATCHED AND t.id = 1 THEN
  UPDATE SET s = vals.s
WHEN MATCHED THEN
  DELETE
WHEN NOT MATCHED THEN
  INSERT (id, s)
  VALUES (vals.id, vals.s);"

p

###############################################################################
h 'Переходные таблицы'

c 'Напишем триггерную функцию, показывающую содержимое переходных таблиц. Здесь мы используем имена old_table и new_table, которые будут объявлены при создании триггера.'
c 'Переходные таблицы «выглядят» настоящими, но не присутствуют в системном каталоге и располагаются в оперативной памяти (хотя и могут сбрасываться на диск при большом объеме).'

s 1 "CREATE OR REPLACE FUNCTION transition() RETURNS trigger
AS \$\$
DECLARE
    rec record;
BEGIN
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        RAISE NOTICE 'Старое состояние:';
        FOR rec IN SELECT * FROM old_table LOOP
            RAISE NOTICE '%', rec;
        END LOOP;
    END IF;
    IF TG_OP = 'UPDATE' OR TG_OP = 'INSERT' THEN
        RAISE NOTICE 'Новое состояние:';
        FOR rec IN SELECT * FROM new_table LOOP
            RAISE NOTICE '%', rec;
        END LOOP;
    END IF;
    RETURN NULL;
END
\$\$ LANGUAGE plpgsql;"

c 'Создадим новую таблицу:'

s 1 'CREATE TABLE trans(
    id integer PRIMARY KEY,
    n integer
);'
s 1 "INSERT INTO trans VALUES (1,10), (2,20), (3,30);"

c 'Чтобы при выполнении операции создавались переходные таблицы, необходимо указывать их имена при создании триггера:'

s 1 'CREATE TRIGGER t_after_upd_trans
AFTER UPDATE ON trans -- только одно событие на один триггер
REFERENCING
    OLD TABLE AS old_table
    NEW TABLE AS new_table -- можно и одну, не обязательно обе
FOR EACH STATEMENT
EXECUTE FUNCTION transition();'

c 'Проверим:'

s 1 "UPDATE trans SET n = n + 1 WHERE n <= 20;"

c 'Переходные таблицы содержат только те строки, которые были затронуты операцией.'
c 'Для операций вставки и удаления переходные таблицы работают точно так же, но доступна будет только одна из таблиц: NEW TABLE или OLD TABLE соответственно.'
c 'Поскольку триггеры AFTER ROW срабатывают после выполнения всей операции, переходные таблицы можно использовать и в них. Но обычно это не имеет смысла.'

P 13

###############################################################################
h 'Примеры использования триггеров'

c 'Пример 1: сохранение истории изменения строк.'

c 'Пусть есть таблица, содержащая актуальные данные. Задача состоит в том, чтобы в отдельной таблице сохранять всю историю изменения строк основной таблицы.'
c 'Поддержку исторической таблицы можно было бы возложить на приложение, но тогда велика вероятность, что в каких-то случаях из-за ошибок история не будет сохраняться. Поэтому решим задачу с помощью триггера.'

c 'Основная таблица:'

s 1 "CREATE TABLE coins(
    face_value numeric PRIMARY KEY,
    name text
);"

c 'Историческая таблица должна называться так же, как основная, но заканчиваться на «_history». Сначала создаем клон основной таблицы...'

s 1 "CREATE TABLE coins_history(LIKE coins);"

c '...и затем добавляем столбцы «действительно с» и «действительно по»:'

s 1 "ALTER TABLE coins_history
    ADD start_date timestamp,
    ADD end_date timestamp;"

c 'Одна триггерная функция будет вставлять новую историческую строку с открытым интервалом действия:'

s 1 "CREATE OR REPLACE FUNCTION history_insert() RETURNS trigger
AS \$\$
BEGIN
    EXECUTE format(
        'INSERT INTO %I SELECT (\$1).*, current_timestamp, NULL',
        TG_TABLE_NAME||'_history'
    ) USING NEW;

    RETURN NEW;
END
\$\$ LANGUAGE plpgsql;"

c 'Другая функция будет закрывать интервал действия исторической строки:'

s 1 "CREATE OR REPLACE FUNCTION history_delete() RETURNS trigger
AS \$\$
BEGIN
    EXECUTE format(
        'UPDATE %I SET end_date = current_timestamp WHERE face_value = \$1 AND end_date IS NULL',
        TG_TABLE_NAME||'_history'
    ) USING OLD.face_value;

    RETURN OLD;
END
\$\$ LANGUAGE plpgsql;"

c 'Теперь создадим триггеры. Важные моменты:'
ul 'Обновление трактуется как удаление и последующая вставка; здесь важен порядок, в котором сработают триггеры (по алфавиту).'
ul 'Current_timestamp возвращает время начала транзакции, поэтому при обновлении start_date одной строки будет равен end_date другой.'
ul 'Использование AFTER-триггеров позволяет избежать проблем с INSERT ... ON CONFLICT и потенциальными конфликтами с другими триггерами, которые могут существовать на основной таблице.'

s 1 "CREATE TRIGGER coins_history_insert
AFTER INSERT OR UPDATE ON coins
FOR EACH ROW EXECUTE FUNCTION history_insert();"
s 1 "CREATE TRIGGER coins_history_delete
AFTER UPDATE OR DELETE ON coins
FOR EACH ROW EXECUTE FUNCTION history_delete();"

c 'Проверим работу триггеров.'

s 1 "INSERT INTO coins VALUES (0.25, 'Полушка'), (3, 'Алтын');"

export DATE=`psql -A -t -X -d $TOPIC_DB -c "SELECT current_timestamp;"`

sleep-ni 2
s 1 "UPDATE coins SET name = '3 копейки' WHERE face_value = 3;"
sleep-ni 1
s 1 "INSERT INTO coins VALUES (5, '5 копеек');"
sleep-ni 2
s 1 "DELETE FROM coins WHERE face_value = 0.25;"

s 1 "SELECT * FROM coins;"

c 'В исторической таблице хранится вся история изменений:'

s 1 "SELECT * FROM coins_history ORDER BY face_value, start_date;"

c 'И теперь по ней можно восстановить состояние на любой момент времени (это немного напоминает работу механизма MVCC). Например, на самое начало:'

s 1 "\set d '"$DATE"'"
s 1 "SELECT face_value, name
FROM coins_history
WHERE start_date <= :'d' AND (end_date IS NULL OR :'d' < end_date)
ORDER BY face_value;"

p

###############################################################################
h 'Примеры использования триггеров'

c 'Пример 2: обновляемое представление.'

c 'Пусть имеются две таблицы: аэропорты и рейсы:'

s 1 "CREATE TABLE airports(
    code char(3) PRIMARY KEY,
    name text NOT NULL
);"
s 1 "INSERT INTO airports VALUES
    ('SVO', 'Москва. Шереметьево'),
    ('LED', 'Санкт-Петербург. Пулково'),
    ('TOF', 'Томск. Богашево');"

s 1 "CREATE TABLE flights(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    airport_from char(3) NOT NULL REFERENCES airports(code),
    airport_to   char(3) NOT NULL REFERENCES airports(code),
    UNIQUE (airport_from, airport_to)
);"

s 1 "INSERT INTO flights(airport_from, airport_to) VALUES
    ('SVO','LED');"

c 'Для удобства можно определить представление:'

s 1 "CREATE VIEW flights_v AS
SELECT id,
       (SELECT name
        FROM airports
        WHERE code = airport_from) airport_from,
       (SELECT name
        FROM airports
        WHERE code = airport_to) airport_to
FROM flights;"

s 1 "SELECT * FROM flights_v;"

c 'Но такое представление не допускает изменений. Например, не получится изменить пункт назначения таким образом:'

s 1 "UPDATE flights_v
SET airport_to = 'Томск. Богашево'
WHERE id = 1;"

c 'Однако мы можем определить триггер. Триггерная функция может выглядеть, например, так (для краткости обрабатываем только аэропорт назначения, но не составит труда добавить и аэропорт вылета):'

s 1 "CREATE OR REPLACE FUNCTION flights_v_update() RETURNS trigger
AS \$\$
DECLARE
    code_to char(3);
BEGIN
    BEGIN
        SELECT code INTO STRICT code_to
        FROM airports
        WHERE name = NEW.airport_to;
    EXCEPTION
        WHEN no_data_found THEN
            RAISE EXCEPTION 'Аэропорт \"%\" отсутствует', NEW.airport_to;
    END;
    UPDATE flights
    SET airport_to = code_to
    WHERE id = OLD.id; -- изменение id игнорируем
    RETURN NEW;
END
\$\$ LANGUAGE plpgsql;"

c 'И сам триггер:'

s 1 "CREATE TRIGGER flights_v_upd_trigger
INSTEAD OF UPDATE ON flights_v
FOR EACH ROW EXECUTE FUNCTION flights_v_update();"

c 'Проверим:'

s 1 "UPDATE flights_v
SET airport_to = 'Томск. Богашево'
WHERE id = 1;"
s 1 "SELECT * FROM flights_v;"

c 'Попытка изменить аэропорт на отсутствующий в таблице:'

s 1 "UPDATE flights_v
SET airport_to = 'Южно-Сахалинск. Хомутово'
WHERE id = 1;"

###############################################################################
#h 'Триггеры с параметрами'
#
#c 'Параметры позволяют передать триггерной функции дополнительный контекст, если стандартных TG-переменных недостаточно.'
#c 'Допустим, мы хотим заполнять поле первичного ключа таблиц значением последовательности.'
#
#s 1 "CREATE OR REPLACE FUNCTION get_id() RETURNS trigger AS \$\$
#BEGIN
#    NEW.id := nextval(TG_ARGV[0]);
#    RETURN NEW;
#END;
#\$\$ LANGUAGE plpgsql;"
#
#s 1 "CREATE TABLE t1(
#    id integer PRIMARY KEY,
#    s text
#);"
#s 1 'CREATE SEQUENCE t1_seq;'
#s 1 "CREATE TABLE t2(
#    id integer PRIMARY KEY,
#    s text
#);"
#s 1 'CREATE SEQUENCE t2_seq;'
#
#s 1 "CREATE TRIGGER t1_get_id
#BEFORE INSERT ON t1
#FOR EACH ROW EXECUTE FUNCTION get_id('t1_seq');"
#s 1 "CREATE TRIGGER t2_get_id
#BEFORE INSERT ON t2
#FOR EACH ROW EXECUTE FUNCTION get_id('t2_seq');"
#
#p
#
#s 1 "INSERT INTO t1(s) VALUES ('a'),('b') RETURNING *;"
#s 1 "INSERT INTO t2(s) VALUES ('a'),('b') RETURNING *;"
#
#p

###############################################################################
#h 'Правила видимости'
#
#c 'Триггерная функция может читать данные из любых таблиц, в том числе и из той, которая изменяется текущим оператором. Делать так, скорее всего, не стоит — но тем не менее посмотрим на правила видимости на примере удаления строк.'
#
#c 'Таблица:'
#
#s 1 "CREATE TABLE t2(
#    id integer
#);"
#
#p
#
#c 'Триггерная функция, не вмешиваясь в работу, печатает содержимое таблицы — как она его видит.'
#
#s 1 "CREATE OR REPLACE FUNCTION selfie() RETURNS trigger AS \$\$
#DECLARE
#    r record;
#BEGIN
#    RAISE NOTICE '% % of %', TG_WHEN, TG_OP, OLD;
#    FOR r IN (SELECT * FROM t2) LOOP
#        RAISE NOTICE '  %', r;
#    END LOOP;
#    RAISE NOTICE '---';
#    RETURN OLD;
#END;
#\$\$ VOLATILE LANGUAGE plpgsql;"
#
#p
#
#c 'Функция будет вызываться в двух триггерах — до и после удаления строки.'
#
#s 1 "CREATE TRIGGER t2_before
#BEFORE DELETE ON t2
#FOR EACH ROW EXECUTE FUNCTION selfie();"
#s 1 "CREATE TRIGGER t2_after
#AFTER DELETE ON t2
#FOR EACH ROW EXECUTE FUNCTION selfie();"
#
#p
#
#c 'Пробуем:'
#
#s 1 "INSERT INTO t2 VALUES (1), (2);"
#s 1 "DELETE FROM t2;"
#
#c 'Таким образом, функция, объявленная как VOLATILE, видит изменения в таблице в процессе работы оператора.'
#
#p
#
#c 'Если же триггерная функция объявлена как STABLE (или IMMUTABLE), то она видит таблицу по состоянию на начало оператора:'
#
#s 1 "ALTER FUNCTION selfie() STABLE;"
#
#s 1 "INSERT INTO t2 VALUES (1), (2);"
#s 1 "DELETE FROM t2;"

P 15

###############################################################################
h 'Триггеры событий'

c 'Пример триггера для события ddl_command_end — завершение DDL-операции.'

c 'Создадим функцию, которая описывает контекст вызова:'

s 1 "CREATE OR REPLACE FUNCTION describe_ddl() RETURNS event_trigger
AS \$\$
DECLARE
    r record;
BEGIN
    -- Для события ddl_command_end контекст вызова в специальной функции
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        RAISE NOTICE '%. тип: %, OID: %, имя: % ', 
            r.command_tag, r.object_type, r.objid, r.object_identity;
    END LOOP;
    -- Функции триггера событий не нужно возвращать значение
END
\$\$ LANGUAGE plpgsql;"

c 'Сам триггер:'

s 1 "CREATE EVENT TRIGGER after_ddl 
ON ddl_command_end EXECUTE FUNCTION describe_ddl();"

c 'Создаем новую таблицу:'

s 1 "CREATE TABLE t1(id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY);"

c 'Создание таблицы может может привести к выполнению нескольких команд DDL, поэтому функция pg_event_trigger_ddl_commands возвращает множество строк.'

p

c 'Триггер на событие table_rewrite срабатывает до перезаписи таблицы командами ALTER TABLE и ALTER TYPE. Функция ниже выведет информацию о перезаписываемой таблице и код, описывающий причину перезаписи:'

s 1 "CREATE FUNCTION describe_rewrite() RETURNS event_trigger
AS \$\$
BEGIN
    -- Для события table_rewrite специальные функции возвращают данные:
    RAISE NOTICE 'Будет перезаписана таблица %, код %',
                pg_event_trigger_table_rewrite_oid()::regclass,  -- перезаписываемая таблица
                pg_event_trigger_table_rewrite_reason();  -- код причины перезаписи
END
\$\$ LANGUAGE plpgsql;"

c 'Теперь создаем триггер:'

s 1 "CREATE EVENT TRIGGER before_rewrite
ON table_rewrite EXECUTE FUNCTION describe_rewrite();"

c 'Изменим таблицу — назначим другой тип столбцу id:'

s 1 "ALTER TABLE t1 ALTER COLUMN id type bigint;"

c 'Хотя перезапись таблицы может быть вызвана и другими командами, в частности CLUSTER и VACUUM FULL, событие table_rewrite для них не вызывается.'


###############################################################################

stop_here
cleanup
demo_end
