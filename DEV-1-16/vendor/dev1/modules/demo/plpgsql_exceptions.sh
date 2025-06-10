#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
psql_open A 2
s 2 "\c $TOPIC_DB"

start_here 4

###############################################################################
h 'Обработка ошибок в блоке'

c 'Рассмотрим простой пример.'

s 1 "CREATE TABLE t(id integer);"
s 1 "INSERT INTO t(id) VALUES (1);"

c 'Когда нет ошибок, все операторы блока выполняются обычным образом:'

s 1 "DO \$\$
DECLARE
    n integer;
BEGIN
    SELECT id INTO STRICT n FROM t;
    RAISE NOTICE 'Оператор SELECT INTO выполнился, n = %', n;
END
\$\$;"

c 'Теперь добавим в таблицу «лишнюю» строку, чтобы спровоцировать ошибку.'

s 1 "INSERT INTO t(id) VALUES (2);"

c 'Если в блоке нет секции EXCEPTION, выполнение операторов в блоке прерывается и весь блок считается завершившимся с ошибкой:'

s 1 "DO \$\$
DECLARE
    n integer;
BEGIN
    SELECT id INTO STRICT n FROM t;
    RAISE NOTICE 'Оператор SELECT INTO выполнился, n = %', n;
END
\$\$;"

c 'Чтобы перехватить ошибку, в блоке нужна секция EXCEPTION, определяющая обработчик или несколько обработчиков.'
c 'Эта конструкция работает аналогично CASE: условия просматриваются сверху вниз, выбирается первая подходящая ветвь и выполняются ее операторы.'
c 'Что будет выведено?'

s 1 "DO \$\$
DECLARE
    n integer;
BEGIN
    n := 3;
    INSERT INTO t(id) VALUES (n);
    SELECT id INTO STRICT n FROM t;
    RAISE NOTICE 'Оператор SELECT INTO выполнился, n = %', n;
EXCEPTION
    WHEN no_data_found THEN
        RAISE NOTICE 'Нет данных';
    WHEN too_many_rows THEN
        RAISE NOTICE 'Слишком много данных';
        RAISE NOTICE 'Строк в таблице: %, n = %', (SELECT count(*) FROM t), n;
END
\$\$;"

c 'Выполняется обработчик, соответствующий ошибке too_many_rows. Обратите внимание: после обработки в таблице остается 2 строки, так как перед выполнением обработчика произошел откат к неявной точке сохранения, которая устанавливается в начале блока.'

c 'Также заметьте, что локальная переменная функции сохранила то значение, которое было на момент возникновения ошибки.'

p

c 'Тонкий момент: если ошибка произойдет в секции DECLARE или в самом обработчике внутри EXCEPTION, то в этом блоке ее перехватить не получится.'

s 1 "DO \$\$
DECLARE
    n integer := 1 / 0; -- ошибка в этом месте не перехватывается
BEGIN
    RAISE NOTICE 'Все успешно';
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Деление на ноль';
END
\$\$;"

P 6

###############################################################################
h 'Имена и коды ошибок'

c 'Имена ошибок мы уже видели, а для указания кода служит конструкция SQLSTATE.'
c 'В обработчике можно получить код ошибки и сообщение с помощью предопределенных переменных SQLSTATE и SQLERRM (вне блока EXCEPTION эти переменные не определены).'

s 1 "DO \$\$
DECLARE
    n integer;
BEGIN
    SELECT id INTO STRICT n FROM t;
EXCEPTION
    WHEN SQLSTATE 'P0003' OR no_data_found THEN -- можно несколько
        RAISE NOTICE '%: %', SQLSTATE, SQLERRM;
END
\$\$;"

c 'Какой обработчик будет использован?'

s 1 "DO \$\$
DECLARE
    n integer;
BEGIN
    SELECT id INTO STRICT n FROM t;
EXCEPTION
    WHEN no_data_found THEN
        RAISE NOTICE 'Нет данных. %: %', SQLSTATE, SQLERRM;
    WHEN plpgsql_error THEN
        RAISE NOTICE 'Другая ошибка. %: %', SQLSTATE, SQLERRM;
    WHEN too_many_rows THEN
        RAISE NOTICE 'Слишком много данных. %: %', SQLSTATE, SQLERRM;
END
\$\$;"

c 'Выбирается первый подходящий обработчик, в данном случае — plpgsql_error (напомним, что это не отдельная ошибка, а категория). До последнего обработчика дело никогда не дойдет.'

p

c 'Ошибку можно принудительно вызвать по ее коду или имени.'
c 'Здесь мы используем специальное имя others, соответствующее любой ошибке, которую можно перехватить (за исключением прерванного клиентом выполнения и нарушения отладочной проверки assert — их можно перехватить отдельно, но обычно это не имеет смысла).'

s 1 "DO \$\$
BEGIN
    RAISE no_data_found;
EXCEPTION
    WHEN others THEN
        RAISE NOTICE '%: %', SQLSTATE, SQLERRM;
END
\$\$;"

c 'При необходимости можно задействовать и пользовательские коды ошибок, отсутствующие в справочнике, а также указать некоторую дополнительную информацию (в примере — только часть из возможного):'

s 1 "DO \$\$
BEGIN
    RAISE SQLSTATE 'ERR01' USING
        message := 'Сбой матрицы',
        detail  := 'При выполнении произошел непоправимый сбой матрицы',
        hint := 'Обратитесь к системному администратору';
END
\$\$;"

c 'В обработчике эту информацию нельзя получить из переменных; если нужно проанализировать такие данные в коде, есть специальная конструкция:'

s 1 "DO \$\$
DECLARE
    message text;
    detail text;
    hint text;
BEGIN
    RAISE SQLSTATE 'ERR01' USING
        message := 'Сбой матрицы',
        detail  := 'При выполнении произошел непоправимый сбой матрицы',
        hint := 'Обратитесь к системному администратору';
EXCEPTION
    WHEN others THEN
        GET STACKED DIAGNOSTICS
            message := MESSAGE_TEXT,
            detail := PG_EXCEPTION_DETAIL,
            hint := PG_EXCEPTION_HINT;
        RAISE NOTICE E'\nmessage = %\ndetail = %\nhint = %',
            message, detail, hint;
END
\$\$;"

P 8

###############################################################################
h 'Поиск обработчика'

c 'Рассмотрим несколько примеров поиска обработчика в случае вложенных блоков. Что будет выведено?'

s 1 "DO \$\$
BEGIN
    BEGIN
        SELECT 1/0;
        RAISE NOTICE 'Вложенный блок выполнен';
    EXCEPTION
        WHEN division_by_zero THEN
            RAISE NOTICE 'Ошибка во вложенном блоке';
    END;
    RAISE NOTICE 'Внешний блок выполнен';
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Ошибка во внешнем блоке';
END
\$\$;"

c 'Ошибка обрабатывается в том блоке, в котором она возникла. Внешний блок выполняется так, как будто никакой ошибки не было.'

p

c 'А так?'

s 1 "DO \$\$
BEGIN
    BEGIN
        SELECT 1/0;
        RAISE NOTICE 'Вложенный блок выполнен';
    EXCEPTION
        WHEN no_data_found THEN
            RAISE NOTICE 'Ошибка во вложенном блоке';
    END;
    RAISE NOTICE 'Внешний блок выполнен';
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Ошибка во внешнем блоке';
END
\$\$;"

c 'Обработчик во внутреннем блоке не подходит; блок завершается с ошибкой, которая обрабатывается уже во внешнем блоке.'
c 'Не забывайте, что в блоке с секцией EXCEPTION происходит откат к точке сохранения, неявно установленной в начале блока. В данном случае будут отменены все изменения, сделанные в обоих блоках.'

p

c 'А так?'

s 1 "DO \$\$
BEGIN
    BEGIN
        SELECT 1/0;
        RAISE NOTICE 'Вложенный блок выполнен';
    EXCEPTION
        WHEN no_data_found THEN
            RAISE NOTICE 'Ошибка во вложенном блоке';
    END;
    RAISE NOTICE 'Внешний блок выполнен';
EXCEPTION
    WHEN no_data_found THEN
        RAISE NOTICE 'Ошибка во внешнем блоке';
END
\$\$;"

c 'Так не срабатывает ни один обработчик, и вся транзакция обрывается.'

c 'Обычно не нужно стремиться обработать все возможные ошибки в серверном коде. Нет ничего плохого в том, чтобы передать возникшую ошибку клиенту. В целом, обрабатывать ошибку имеет смысл на том уровне, на котором можно сделать что-то осмысленное в возникшей ситуации. Поэтому обрабатывать ошибку внутри базы данных стоит, когда можно что-то сделать именно на серверной стороне (например, повторить операцию при ошибке сериализации). Про журналирование сообщений об ошибках мы еще будем говорить в теме «PL/pgSQL. Отладка».'

p

c 'Теперь рассмотрим пример с подпрограммами.'

s 1 "CREATE PROCEDURE foo()
AS \$\$
BEGIN
    CALL bar();
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE PROCEDURE bar()
AS \$\$
BEGIN
    CALL baz();
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE PROCEDURE baz()
AS \$\$
BEGIN
    PERFORM 1 / 0;
END
\$\$ LANGUAGE plpgsql;"

c 'Что произойдет при вызове?'

s 1 'CALL foo();'

c 'То, что мы видим в сообщении об ошибке — это стек вызовов: сверху вниз = изнутри наружу.'
c 'Заметьте, что в этом сообщении, как и во многих других, вместо слова procedure используется function.'

p

c 'В обработчике ошибки тоже можно получить доступ к стеку, правда, в виде одной строки:'

s 1 "CREATE OR REPLACE PROCEDURE bar()
AS \$\$
DECLARE
    msg text;
    ctx text;
BEGIN
    CALL baz();
EXCEPTION
    WHEN others THEN
        GET STACKED DIAGNOSTICS
             msg := MESSAGE_TEXT,
             ctx := PG_EXCEPTION_CONTEXT;
        RAISE NOTICE E'\nОшибка: %\nСтек ошибки:\n%\n', msg, ctx;
END
\$\$ LANGUAGE plpgsql;"

c 'Проверим:'

s 1 'CALL foo();'

p

c 'Поскольку блок с секцией EXCEPTION устанавливает неявную точку сохранения, то и в этом блоке, и во всех блоках выше по стеку вызовов, процедуры лишаются возможности использовать команды COMMIT и ROLLBACK.'

s 1 "CREATE OR REPLACE PROCEDURE baz()
AS \$\$
BEGIN
    COMMIT;
END
\$\$ LANGUAGE plpgsql;"

s 1 'CALL foo();'

P 10

###############################################################################
h 'Накладные расходы'

c 'Чтобы оценить накладные расходы, рассмотрим простой пример.'

c 'Пусть имеется таблица с текстовым полем, в которое пользователи заносят произвольные данные (обычно это признак неудачного дизайна, но иногда приходится). Нам нужно выделить числа в отдельный столбец числового типа.'

s 1 "CREATE TABLE data(comment text, n integer);"
s 1 "INSERT INTO data(comment)
SELECT CASE
        WHEN random() < 0.01 THEN 'не число' --  1%
        ELSE (random()*1000)::integer::text  -- 99%
    END
FROM generate_series(1,1_000_000);"

c 'Решим задачу с помощью обработки ошибок, возникающих при преобразовании текстовых данных к числу:'

s 1 "CREATE FUNCTION safe_to_integer_ex(s text) RETURNS integer
AS \$\$
BEGIN
    RETURN s::integer;
EXCEPTION
    WHEN invalid_text_representation THEN
        RETURN NULL;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

c 'Проверим:'
s 1 '\timing on'
s 1 "UPDATE data SET n = safe_to_integer_ex(comment);"
s 1 '\timing off'

s 1 "SELECT count(*) FROM data WHERE n IS NOT NULL;"

c 'В другом варианте функции вместо обработки ошибки будем проверять формат с помощью регулярного выражения (слегка упрощенного):'

s 1 "CREATE FUNCTION safe_to_integer_re(s text) RETURNS integer
AS \$\$
BEGIN
    RETURN CASE
        WHEN s ~ '^\d+$' THEN s::integer
        ELSE NULL
    END;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

c 'Проверим этот вариант:'
s 1 '\timing on'
s 1 "UPDATE data SET n = safe_to_integer_re(comment);"
s 1 '\timing off'

s 1 "SELECT count(*) FROM data WHERE n IS NOT NULL;"

c 'Получается заметно быстрее. В этом примере исключение срабатывало всего в 1% случаев. Чем чаще — тем больше будет дополнительных накладных расходов на откат к точке сохранения.'

s 1 "UPDATE data SET comment = 'не число'; -- 100%"
s 1 '\timing on'
s 1 "UPDATE data SET n = safe_to_integer_ex(comment);"
s 1 '\timing off'

p

c 'Встречаются (и довольно часто) случаи, когда можно обойтись без обработки ошибок, если выбрать другие подходящие средства.'

c 'Задача: вернуть строку из справочника или NULL, если строки нет.'

s 1 'CREATE TABLE categories(code text UNIQUE, description text);'
s 1 "INSERT INTO categories VALUES ('books','Книги'), ('discs','Диски');"

c 'Функция с обработкой ошибки:'

s 1 "CREATE FUNCTION get_cat_desc(code text) RETURNS text
AS \$\$
DECLARE
    desc text;
BEGIN
    SELECT c.description INTO STRICT desc
    FROM categories c
    WHERE c.code = get_cat_desc.code;

    RETURN desc;
EXCEPTION
    WHEN no_data_found THEN
        RETURN NULL;
END
\$\$ STABLE LANGUAGE plpgsql;"

c 'Проверим, что функция работает правильно:'

s 1 "SELECT get_cat_desc('books');"
s 1 "SELECT get_cat_desc('movies');"

c 'Можно ли проще?'

p

c 'Да, надо просто убрать STRICT или использовать подзапрос:'

s 1 "CREATE OR REPLACE FUNCTION get_cat_desc(code text) RETURNS text
AS \$\$
BEGIN
    RETURN (SELECT c.description
            FROM categories c
            WHERE c.code = get_cat_desc.code);
END
\$\$ STABLE LANGUAGE plpgsql;"

c 'В таком варианте хорошо видно, что PL/pgSQL тут вообще не нужен — достаточно SQL.'

c 'Проверим:'

s 1 "SELECT get_cat_desc('books');"
s 1 "SELECT get_cat_desc('movies');"

p

c 'Задача: обновить строку таблицы с определенным идентификатором, а если такой строки нет — вставить ее.'

c 'Первый подход. Что здесь плохо?'

s 1 "CREATE OR REPLACE FUNCTION change(code text, description text)
RETURNS void
AS \$\$
DECLARE
    cnt integer;
BEGIN
    SELECT count(*) INTO cnt
    FROM categories c WHERE c.code = change.code;

    IF cnt = 0 THEN
        INSERT INTO categories VALUES (code, description);
    ELSE
        UPDATE categories c
        SET description = change.description
        WHERE c.code = change.code;
    END IF;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Плохо практически все, начиная с того, что такая функция будет работать некорректно на уровне изоляции Read Committed при наличии нескольких параллельно выполняющихся сеансов. Причина в том, что после выполнения SELECT и перед следующей операцией данные в базе могут измениться.'

c 'Это легко продемонстрировать, если добавить задержку между командами. Для разнообразия возьмем немного другой (но тоже неправильный) вариант:'

s 1 "CREATE OR REPLACE FUNCTION change(code text, description text)
RETURNS void
AS \$\$
BEGIN
    UPDATE categories c
    SET description = change.description
    WHERE c.code = change.code;

    IF NOT FOUND THEN
        PERFORM pg_sleep(1); -- тут может произойти все, что угодно
        INSERT INTO categories VALUES (code, description);
    END IF;
END
\$\$ VOLATILE LANGUAGE plpgsql;"
p

c 'Теперь выполним функцию в двух сеансах почти одновременно:'

ss 1 "SELECT change('games', 'Игры');"
si 2 "SELECT change('games', 'Игры');"
r 1

p

c 'Правильное решение можно построить с помощью обработки ошибки:'

s 1 "CREATE OR REPLACE FUNCTION change(code text, description text)
RETURNS void
AS \$\$
BEGIN
    LOOP
        UPDATE categories c
        SET description = change.description
        WHERE c.code = change.code;

        EXIT WHEN FOUND;
        PERFORM pg_sleep(1); -- для демонстрации

        BEGIN
            INSERT INTO categories VALUES (code, description);
            EXIT;
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;
    END LOOP;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Проверим.'

ss 1 "SELECT change('vynil', 'Грампластинки');"
si 2 "SELECT change('vynil', 'Грампластинки');"
r 1

c 'Да, теперь все правильно.'

p

c 'Но можно решить задачу проще с помощью варианта команды INSERT, который пробует выполнить вставку, а при возникновении конфликта — обновление. И снова достаточно простого SQL.'

s 1 "CREATE OR REPLACE FUNCTION change(code text, description text)
RETURNS void
VOLATILE LANGUAGE sql
BEGIN ATOMIC
    INSERT INTO categories VALUES (code, description)
    ON CONFLICT(code)
        DO UPDATE SET description = change.description;
END;"

p

c 'Задача: гарантировать, что данные обрабатываются одновременно только одним процессом (на уровне изоляции Read Committed).'

c 'Используя ту же таблицу, представим, что периодически категория требует специальной однопоточной обработки. Можно написать функцию следующим образом:'

s 1 "CREATE OR REPLACE FUNCTION process_cat(code text) RETURNS text
AS \$\$
BEGIN
    PERFORM c.code FROM categories c WHERE c.code = process_cat.code
        FOR UPDATE NOWAIT;  -- пробуем блокировать строку без ожидания
    PERFORM pg_sleep(1); -- собственно обработка
    RETURN 'Категория обработана';
EXCEPTION
    WHEN lock_not_available THEN
        RETURN 'Другой процесс уже обрабатывает эту категорию';
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Проверим, что все правильно:'

ss 1 "SELECT process_cat('books');"
si 2 "SELECT process_cat('books');"
r 1

p

c 'Но и эту задачу можно решить без обработки ошибок, используя рекомендательные блокировки:'

s 1 "CREATE OR REPLACE FUNCTION process_cat(code text) RETURNS text
AS \$\$
BEGIN
    IF pg_try_advisory_xact_lock(hashtext(code)) THEN
        PERFORM pg_sleep(1); -- собственно обработка
        RETURN 'Категория обработана';
    ELSE
        RETURN 'Другой процесс уже обрабатывает эту категорию';
    END IF;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Проверим:'

ss 1 "SELECT process_cat('books');"
si 2 "SELECT process_cat('books');"
r 1

p

c 'Приведем и пример, когда без обработки ошибок не обойтись.'

c 'Задача: организовать обработку пакета документов; ошибка при обработке одного документа не должна приводить к общему сбою.'

s 1 "CREATE TYPE doc_status AS ENUM -- тип перечисления
    ('READY', 'ERROR', 'PROCESSED');"
s 1 "CREATE TABLE documents(
    id integer,
    version integer,
    status doc_status,
    message text
);"
s 1 "INSERT INTO documents(id, version, status)
    SELECT id, 1, 'READY' FROM generate_series(1,100) id;"

c 'Процедура, обрабатывающая один документ, иногда приводит к ошибке:'

s 1 "CREATE PROCEDURE process_one_doc(id integer)
AS \$\$
BEGIN
    UPDATE documents d
    SET version = version + 1
    WHERE d.id = process_one_doc.id;
    -- обработка может длиться долго
    IF random() < 0.05 THEN
        RAISE EXCEPTION 'Случилось страшное';
    END IF;
END
\$\$ LANGUAGE plpgsql;"

c 'Теперь напишем процедуру, обрабатывающую все документы. Она вызывает в цикле обработку одного документа и при необходимости обрабатывает ошибку.'
c 'Обратите внимание, что фиксация транзакции выполняется вне блока с секцией EXCEPTION.'

s 1 "CREATE PROCEDURE process_docs()
AS \$\$
DECLARE
    doc record;
BEGIN
    FOR doc IN (SELECT id FROM documents WHERE status = 'READY')
    LOOP
        BEGIN
            CALL process_one_doc(doc.id);

            UPDATE documents d
            SET status = 'PROCESSED'
            WHERE d.id = doc.id;
        EXCEPTION
            WHEN others THEN
                UPDATE documents d
                SET status = 'ERROR', message = sqlerrm
                WHERE d.id = doc.id;
        END;
        COMMIT; -- каждый документ в своей транзакции
    END LOOP;
END
\$\$ LANGUAGE plpgsql;"

c 'Такую же обработку можно организовать и при помощи функции, но тогда все документы будут обрабатываться в одной общей транзакции, что может приводить к проблемам, если обработка выполняется долго. Этот вопрос детально изучается в курсе DEV2.'

c 'Проверим результат:'

s 1 "CALL process_docs();"
s 1 "SELECT d.status, d.version, count(*)::integer
FROM documents d
GROUP BY d.status, d.version;"

c 'Как видим, часть документов не обработалась, но это не помешало обработке остальных.'
c 'Информация об ошибках удобно сохраняется в самой таблице:'

s 1 "SELECT * FROM documents d WHERE d.status = 'ERROR';"

c 'И еще раз обратим внимание, что при возникновении ошибки происходит откат к точке сохранения в начале блока: благодаря этому версии документов в статусе ERROR остались равными 1.'

###############################################################################

stop_here
cleanup
demo_end
