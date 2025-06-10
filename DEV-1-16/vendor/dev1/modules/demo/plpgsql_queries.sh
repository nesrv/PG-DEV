#!/bin/bash

. ../lib

init

psql_open A 1

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

start_here 4

###############################################################################
h 'Команды, не возвращающие результат'

c 'Если результат запроса не нужен, заменяем SELECT на PERFORM:'

s 1 "CREATE FUNCTION do_something() RETURNS void
AS \$\$
BEGIN
    RAISE NOTICE 'Что-то сделалось.';
END
\$\$ LANGUAGE plpgsql;"

s 1 "DO \$\$
BEGIN
    PERFORM do_something();
END
\$\$;"

p

c 'Внутри PL/pgSQL можно использовать без изменений практически любые команды SQL, не возвращающие результат:'

s 1 "DO \$\$
BEGIN
    CREATE TABLE test(n integer);
    INSERT INTO test VALUES (1),(2),(3);
    UPDATE test SET n = n + 1 WHERE n > 1;
    DELETE FROM test WHERE n = 1;
    DROP TABLE test;
END
\$\$;"

p

###############################################################################
h 'Управление транзакциями в процедурах'

c 'В процедурах (и в анонимных блоках кода) на PL/pgSQL можно использовать команды управления транзакциями:'

s 1 "CREATE TABLE test(n integer);"

s 1 "CREATE PROCEDURE foo()
AS \$\$
BEGIN
    INSERT INTO test VALUES (1);
    COMMIT;
    INSERT INTO test VALUES (2);
    ROLLBACK;
END
\$\$ LANGUAGE plpgsql;"

s 1 "CALL foo();"
s 1 "SELECT * FROM test;"

p

c 'Действуют определенные ограничения. Во-первых, процедура в таких случаях должна сама начинать новую транзакцию, а не выполняться в контексте уже начатой ранее.'

s 1 "BEGIN;"
s 1 "CALL foo(); -- ошибка"
s 1 "ROLLBACK;"

p

c 'Во-вторых, в стеке вызовов процедуры не должно быть ничего, кроме операторов CALL.'

c 'Иными словами, если процедура вызывает процедуру, которая вызывает процедуру... которая выполняет команду управления транзакцией, то все работает:'

s 1 "CREATE OR REPLACE PROCEDURE foo()
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
    COMMIT;
END
\$\$ LANGUAGE plpgsql;"

s 1 "CALL foo(); -- работает"

c 'Но стоит в этой цепочке появиться, например, вызову функции, то получается, что транзакция должна завершиться где-то «посередине» оператора, в контексте которого вызывается эта функция, например SELECT. Это недопустимо, получаем ошибку:'

s 1 "CREATE FUNCTION qux() RETURNS void 
AS \$\$
BEGIN
    CALL bar();
END
\$\$ LANGUAGE plpgsql;"

s 1 "SELECT qux(); -- ошибка"

P 6

###############################################################################
h 'Команды, возвращающие одну строку'

c 'Наверное, наиболее часто используется в PL/pgSQL команда SELECT, возвращающая одну строку. Пример выводит одну строку, хотя запрос внутри анонимного блока возвращает две:'

s 1 'CREATE TABLE t(id integer, code text);'
s 1 "INSERT INTO t VALUES (1, 'Раз'), (2, 'Два');"

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO r FROM t;
    RAISE NOTICE '%', r;
END
\$\$;"

c 'Обратите внимание, что в приведенном коде PostgreSQL есть конструкция, очень похожая на SQL-команду SELECT INTO, в которой после INTO указывается имя новой таблицы, создающейся и наполняющейся результатами запроса. В PL/pgSQL для решения такой задачи нужно использовать эквивалентный синтаксис CREATE TABLE ... AS SELECT.'

p

c 'Команды INSERT, UPDATE, DELETE тоже могут возвращать результат с помощью фразы RETURNING. Их можно использовать в PL/pgSQL точно так же, как SELECT, добавив фразу INTO:'

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    UPDATE t SET code = code || '!' WHERE id = 1 RETURNING * INTO r;
    RAISE NOTICE 'Изменили: %', r;
END
\$\$;"

p

###############################################################################
h 'Проверки при создании и при выполнении подпрограмм'

c 'PL/pgSQL может выдавать предупреждения в некоторых подозрительных случаях. Для этого надо установить параметр (значение по умолчанию — none):'

s 1 "SET plpgsql.extra_warnings = 'all';"

s 1 "CREATE PROCEDURE bugs(INOUT a integer)
AS \$\$
DECLARE
    a integer;
    b integer;
BEGIN
    SELECT id INTO a, b FROM t;
END
\$\$ LANGUAGE plpgsql;"

c 'Это предупреждение о перекрывающих друг друга определениях переменных.'

s 1 "CALL bugs(42);"

c 'А здесь мы видим два предупреждения времени выполнения: запрос вернул более одной строки, а в предложении INTO указано неверное число параметров (PL/pgSQL присвоит второму неопределенное значение). Других проверок в настоящее время не предусмотрено, но они могут появиться в следующих версиях PostgreSQL.'

c 'Значение параметра plpgsql.extra_warnings можно ограничить только определенными проверками. Аналогичный параметр plpgsql.extra_errors будет приводить не к предупреждениям, а к ошибкам.'

s 1 "RESET plpgsql.extra_warnings;"
p

c 'Стороннее расширение plpgsql_check, написанное и развиваемое Павлом Стехуле, позволяет проверить код более детально. Расширение уже установлено в виртуальной машине курса.'

s 1 "CREATE SCHEMA plpgsql_check;"
s 1 "CREATE EXTENSION plpgsql_check SCHEMA plpgsql_check;"
s 1 "SELECT * FROM plpgsql_check.plpgsql_check_function('bugs(integer)');"

c 'Дополнительно обнаружены неиспользуемые переменные и тот факт, что выходному параметру не присваивается значение.'

c 'Расширение имеет множество возможностей для обнаружения проблем в коде, в том числе и на этапе выполнения. Кроме того, расширение включает и профилировщик для целей оптимизации PL/pgSQL-кода.'

p

###############################################################################
h 'Устранение неоднозначностей именования'

c 'Получится ли выполнить следующий код?'

s 1 "DO \$\$
DECLARE
    id   integer := 1;
    code text;
BEGIN
    SELECT id, code INTO id, code
    FROM t WHERE id = id;
    RAISE NOTICE '%, %', id, code;
END
\$\$;"

c 'Не получится из-за неоднозначности в SELECT: id может означать и имя столбца, и имя переменной. Причем во фразе INTO неоднозначности нет — она относится только к PL/pgSQL. В сообщении, кстати, видно, как PL/pgSQL вырезает фразу INTO, прежде чем передать запрос в SQL.'

p

c 'Есть несколько подходов к устранению неоднозначностей.'
c 'Первый состоит в том, чтобы неоднозначностей не допускать. Для этого к переменным добавляют префикс, который обычно выбирается в зависимости от «класса» переменной, например:'
ul 'Для параметров p_ (parameter);'
ul 'Для обычных переменных l_ (local) или v_ (variable);'
ul 'Для констант c_ (constant);'

c 'Это простой и действенный способ, если использовать его систематически и никогда не использовать префиксы в именах столбцов. К минусам можно отнести некоторую неряшливость и пестроту кода из-за лишних подчеркиваний.'

p

c 'Вот как это может выглядеть в нашем случае:'

s 1 "DO \$\$
DECLARE
    l_id   integer := 1;
    l_code text;
BEGIN
    SELECT id, code INTO l_id, l_code
    FROM t WHERE id = l_id;
    RAISE NOTICE '%, %', l_id, l_code;
END
\$\$;"

p

c 'Второй способ состоит в использовании квалифицированных имен — к имени объекта через точку дописывается уточняющий квалификатор:'
ul 'для столбца — имя или псевдоним таблицы;'
ul 'для переменной — метку блока;'
ul 'для параметра — имя функции.'

c 'Такой способ более «честный», чем добавление префиксов, поскольку работает для любых названий столбцов.'

p

c 'Вот как будет выглядеть наш пример с использованием квалификаторов:'

s 1 "DO \$\$
<<local>>
DECLARE
    id   integer := 1;
    code text;
BEGIN
    SELECT t.id, t.code INTO local.id, local.code
    FROM t WHERE t.id = local.id;
    RAISE NOTICE '%, %', id, code;
END
\$\$;"

p

c 'Третий вариант — установить приоритет переменных над столбцами или наоборот, столбцов над переменными. За это отвечает конфигурационный параметр plpgsql.variable_conflict. Его возможные значения use_column, use_variable и error.'

c 'В ряде случаев это упрощает разрешение конфликтов, но не устраняет их полностью. Кроме того, неявное правило (которое, к тому же, может внезапно поменяться) непременно приведет к тому, что какой-то код будет выполняться не так, как предполагал разработчик.'

c 'Тем не менее приведем пример. Здесь устанавливается приоритет переменных, поэтому достаточно квалифицировать только столбцы таблицы:'

s 1 'SET plpgsql.variable_conflict = use_variable;'

s 1 "DO \$\$
DECLARE
    id   integer := 1;
    code text;
BEGIN
    SELECT t.id, t.code INTO id, code
    FROM t WHERE t.id = id;
    RAISE NOTICE '%, %', id, code;
END
\$\$;"

s 1 'RESET plpgsql.variable_conflict;  -- сбросим значение к умолчательному'
s 1 'SHOW plpgsql.variable_conflict;'

c 'Какой способ выбрать — дело опыта и вкуса. Мы рекомендуем остановиться либо на первом (префиксы), либо на втором (квалификаторы), и не смешивать их в одном проекте, поскольку систематичность крайне важна для облегчения понимания кода.'

c 'В курсе мы будем использовать второй способ, но только в тех случаях, когда это действительно необходимо — чтобы не загромождать примеры.'

c 'Однако в коде, предназначенном для промышленной эксплуатации, думать о неоднозначностях надо всегда: нет никакой гарантии, что завтра в таблице не появится новый столбец с именем, совпадающим с вашей переменной!'

P 8

###############################################################################
h 'Ровно одна строка'

c 'Что произойдет, если запрос вернет несколько строк?'

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO r FROM t;
    RAISE NOTICE '%', r;
END
\$\$;"

c 'В переменную будет записана только первая строка. Поскольку мы не указали ORDER BY, то порядок строк в общем случае непредсказуем:'

s 1 "SELECT * FROM t;"

c 'Поскольку в командах INSERT, UPDATE, DELETE нет возможности указать порядок строк, то команда, затрагивающая несколько строк, приводит к ошибке:'

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    UPDATE t SET code = code || '!' RETURNING * INTO r;
    RAISE NOTICE 'Изменили: %', r;
END
\$\$;"

c 'А если запрос не вернет ни одной строки?'

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    r := (-1,'!!!');
    SELECT id, code INTO r FROM t WHERE false;
    RAISE NOTICE '%', r;
END
\$\$;"

c 'Переменные будут содержать неопределенные значения.'

c 'То же относится и командам INSERT, UPDATE, DELETE. Например:'

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    UPDATE t SET code = code || '!' WHERE id = -1
        RETURNING * INTO r;
    RAISE NOTICE 'Изменили: %', r;
END
\$\$;"

c 'Иногда хочется быть уверенным, что в результате выборки получилась ровно одна строка: ни больше, ни меньше. В этом случае удобно воспользоваться фразой INTO STRICT:'

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO STRICT r FROM t;
    RAISE NOTICE '%', r;
END
\$\$;"

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO STRICT r FROM t WHERE false;
    RAISE NOTICE '%', r;
END
\$\$;"

c 'Как мы видели, команды INSERT, UPDATE, DELETE, затрагивающие несколько строк, приводят к ошибке. Фраза STRICT позволяет гарантировать, что строка будет ровно одна (а не ноль):'

s 1 "DO \$\$
DECLARE
    r record;
BEGIN
    UPDATE t SET code = code || '!' WHERE id = -1 RETURNING * INTO STRICT r;
    RAISE NOTICE 'Изменили: %', r;
END
\$\$;"

p

###############################################################################
h 'Явная проверка состояния'

c 'Другая возможность — проверять состояние последней выполненной SQL-команды:'

ul 'Команда GET DIAGNOSTICS позволяет получить количество затронутых строк (ROW_COUNT);'
ul 'Предопределенная логическая переменная FOUND показывает, была ли затронута хотя бы одна строка.'

s 1 "DO \$\$
DECLARE
    r record;
    rowcount integer;
BEGIN
    SELECT id, code INTO r FROM t WHERE false;

    GET DIAGNOSTICS rowcount := ROW_COUNT;
    RAISE NOTICE 'rowcount = %', rowcount;
    RAISE NOTICE 'found = %', FOUND;
END
\$\$;"

s 1 "DO \$\$
DECLARE
    r record;
    rowcount integer;
BEGIN
    SELECT id, code INTO r FROM t;

    GET DIAGNOSTICS rowcount := ROW_COUNT;
    RAISE NOTICE 'rowcount = %', rowcount;
    RAISE NOTICE 'found = %', FOUND;
END
\$\$;"

c 'Заметьте: диагностика не позволяет обнаружить, что запросу соответствует несколько строк. Элемент диагностики ROW_COUNT возвращает единицу, так как только одна строка из полученного набора была помещена в переменную r.'

P 10

###############################################################################
h 'Табличные функции'

c 'Пример табличной функции на PL/pgSQL:'

s 1 "CREATE FUNCTION t() RETURNS TABLE(LIKE t) 
AS \$\$
BEGIN
    RETURN QUERY SELECT id, code FROM t ORDER BY id;
END
\$\$ STABLE LANGUAGE plpgsql;"

s 1 'SELECT * FROM t();'

c 'Другой вариант — возвращать значения построчно.'

s 1 "CREATE FUNCTION days_of_week() RETURNS SETOF text 
AS \$\$
BEGIN
    FOR i IN 7 .. 13 LOOP
        RETURN NEXT to_char(to_date(i::text,'J'),'TMDy');
    END LOOP;
END;
\$\$ STABLE LANGUAGE plpgsql;"


s 1 'SELECT * FROM days_of_week() WITH ORDINALITY;'

c 'Почему функция объявлена как STABLE, а не как IMMUTABLE?'

p

c 'На первый взгляд кажется, что при повторных вызовах функция будет возвращать тот же результат, но на самом деле он неявно зависит от текущей локали:'

s 1 "SET lc_time = 'en_US.UTF8';"
s 1 'SELECT * FROM days_of_week() WITH ORDINALITY;'

p

c 'Еще один пример иллюстрирует «смешанный» подход. Здесь мы создаем функцию, которая возвращает список подпрограмм из своей схемы. Элемент диагностики PG_ROUTINE_OID позволяет функции получить свой oid:'

s 1 "CREATE FUNCTION where_am_i() RETURNS TABLE(name text, isitme text)
AS \$\$
DECLARE
    my_oid oid;
    schema_oid oid;
BEGIN 
    GET DIAGNOSTICS my_oid := PG_ROUTINE_OID;
    -- oid схемы
    schema_oid := pronamespace FROM pg_proc WHERE oid = my_oid;
    -- Заголовок
    name := '=== Схема: ' || schema_oid::regnamespace;
    RETURN NEXT;  -- заголовок с названием схемы
    -- Список подпрограмм
    RETURN QUERY
		SELECT proname::text, CASE WHEN oid = my_oid THEN 'It''s me!' END
		FROM pg_proc
		WHERE pronamespace = schema_oid
		ORDER BY 1;
END
\$\$ STABLE LANGUAGE plpgsql;"

c 'Пробуем вызов:'

s 1 'SELECT * FROM where_am_i();'


###############################################################################

stop_here
cleanup
demo_end
