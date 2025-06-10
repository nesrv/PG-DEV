#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

start_here 5

###############################################################################
h 'Выполнение динамического запроса'

c 'Оператор EXECUTE позволяет выполнить SQL-команду, заданную в виде строки.'

s 1 "DO \$\$
DECLARE
    cmd CONSTANT text := 'CREATE TABLE city_msk(
        name text, architect text, founded integer
    )';
BEGIN
    EXECUTE cmd; -- таблица для исторических зданий Москвы
END
\$\$;"

c 'Предложение INTO оператора EXECUTE позволяет вернуть одну (первую) строку результата в переменную составного типа или несколько скалярных переменных.'
c 'Для проверки результата выполнения динамической команды можно использовать команду GET DIAGNOSTICS, как и в случае статических команд (но не переменную FOUND).'

s 1 "DO \$\$
DECLARE
    rec record;
    cnt bigint;
BEGIN
    EXECUTE 'INSERT INTO city_msk (name, architect, founded) VALUES
                 (''Пашков дом'', ''Василий Баженов'', 1784),
                 (''Ансамбль "Царицыно"'', ''Василий Баженов'', 1776),
                 (''Усадьба Тутолмина'', ''Василий Баженов'', 1788),
                 (''Музей Пушкина'', ''Роман Клейн'', 1898),
                 (''ЦУМ'', ''Роман Клейн'', 1908)
             RETURNING name, architect, founded'
    INTO rec;
    RAISE NOTICE '%', rec;
    GET DIAGNOSTICS cnt := ROW_COUNT;
    RAISE NOTICE 'Добавлено строк: %', cnt;
END
\$\$;"

c 'При необходимости с помощью STRICT можно гарантировать, что команда обработает ровно одну строку.'

p

c "Результат динамического запроса можно обработать в цикле FOR."

s 1 "DO \$\$
DECLARE
    rec record;
BEGIN
    FOR rec IN EXECUTE 'SELECT * FROM city_msk WHERE architect = ''Роман Клейн'' ORDER BY founded'
    LOOP
        RAISE NOTICE '%', rec;
    END LOOP;
END
\$\$;"

c 'Этот же пример с использованием курсора.'

s 1 "DO \$\$
DECLARE
    cur refcursor;
    rec record;
BEGIN
    OPEN cur FOR EXECUTE 'SELECT * FROM city_msk WHERE architect = ''Роман Клейн'' ORDER BY founded';
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE '%', rec;
    END LOOP;
END
\$\$;"

p

c "Оператор RETURN QUERY для возврата строк из функции также может использовать динамические запросы. Напишем функцию, возвращающую все здания, возведенные архитектором до определенной даты. Для этого нам понадобятся параметры:"

s 1 "CREATE FUNCTION sel_msk(architect text, founded integer DEFAULT NULL)
RETURNS SETOF text
AS \$\$
DECLARE
    -- параметры пронумерованы: \$1, \$2...
    cmd text := '
        SELECT name FROM city_msk
        WHERE architect = \$1 AND (\$2 IS NULL OR founded < \$2)';
BEGIN
    RETURN QUERY
        EXECUTE cmd
        USING architect, founded; -- указываем значения по порядку
END
\$\$ LANGUAGE plpgsql;"

s 1 "SELECT * FROM sel_msk('Роман Клейн');"
s 1 "SELECT * FROM sel_msk('Роман Клейн', 1905 );  -- до событий на Красной Пресне"

P 7

###############################################################################
h 'Возможность внедрения SQL-кода'

c 'Перепишем функцию, возвращающую здания, добавив параметр — код города. По задумке такая функция должна позволять обращаться только к таблицам, начинающимся на city_.'

s 1 "CREATE FUNCTION sel_city(
    city_code text, 
    architect text, 
    founded integer DEFAULT NULL
)
RETURNS SETOF text AS \$\$
DECLARE
    cmd text := '
        SELECT name FROM city_' || city_code || '
        WHERE architect = \$1 AND (\$2 IS NULL OR founded < \$2)';
BEGIN
    RAISE NOTICE '%', cmd;
    RETURN QUERY
        EXECUTE cmd
        USING architect, founded;
END
\$\$ LANGUAGE plpgsql;"

c 'Функция правильно работает при «нормальных» значениях параметров:'

s 1 "SELECT * FROM sel_city('msk', 'Василий Баженов');"

c 'Однако злоумышленник может подобрать такое значение, которое изменит синтаксическую конструкцию запроса и позволит ему получить несанкционированный доступ к данным:'

s 1 "SELECT * FROM sel_city('msk WHERE false
        UNION ALL
        SELECT usename FROM pg_user
        UNION ALL
        SELECT name FROM city_msk', '');"

c 'При использовании подготовленных операторов или динамических команд с параметрами это невозможно в принципе, так как структура SQL-запроса фиксируется при синтаксическом разборе. Выражение всегда останется выражением и не сможет превратиться, например, в имя таблицы.'

p

###############################################################################
h 'Формирование динамической команды'

c 'Параметры в предложении USING нельзя использовать для имен объектов (названия таблиц, столбцов и пр.) в динамической команде. Такие идентификаторы необходимо экранировать, чтобы структура запроса не могла измениться:'

s 1 "SELECT format('%I', 'foo'),
          format('%I', 'foo bar'),
          format('%I', 'foo\"bar');"

c 'То же самое выполняет и другая функция:'

s 1 "SELECT quote_ident('foo'), 
          quote_ident('foo bar'), 
          quote_ident('foo\"bar');"

c 'Вот как может выглядеть пример с созданием таблицы:'

s 1 "DO \$\$
DECLARE
    cmd CONSTANT text := 'CREATE TABLE %I(
        name text, architect text, founded integer
    )';
BEGIN
    EXECUTE format(cmd, 'city_spb'); -- таблица для Санкт-Петербурга
    EXECUTE format(cmd, 'city_nov'); -- таблица для Новгорода
END
\$\$;"

p

c 'Вместо использования параметров, можно вставлять в строку литералы. В этом случае также требуется экранирование, но другое:'

s 1 "SELECT format('%L', 'foo bar'), 
          format('%L', 'foo''bar'), 
          format('%L', NULL);"

c 'Это же выполняет и функция quote_nullable:'

s 1 "SELECT quote_nullable('foo bar'), 
          quote_nullable('foo''bar'), 
          quote_nullable(NULL);"

c 'Похожая функция quote_literal отличается тем, что не превращает неопределенное значение в литерал:'

s 1 "SELECT quote_literal(NULL);"

p

c "В качестве примера перепишем функцию, возвращающую здания в определенном городе, без использования параметров, но так, чтобы она осталась безопасной."

s 1 "CREATE OR REPLACE FUNCTION sel_city(
    city_code text,
    architect text,
    founded integer DEFAULT NULL
)
RETURNS SETOF text
AS \$\$
DECLARE
    cmd text := '
        SELECT name FROM %I
        WHERE architect = %L AND (%L IS NULL OR founded < %L::integer)';
BEGIN
    RETURN QUERY EXECUTE format(
        cmd, 'city_'||city_code, architect, founded, founded
    );
END
\$\$ LANGUAGE plpgsql;"

c 'Обратите внимание, что в этом случае получается два лишних приведения типов: сначала параметр типа integer приводится к строке, а затем, на этапе выполнения, строка обратно приводится к integer (в случае использования параметров USING такого не происходит):'

s 1 "SELECT * FROM sel_city('msk', 'Василий Баженов', 1785);  -- до приезда императрицы в Царицыно"

c 'Попытка передачи некорректного значения не приведет к успеху:'

s 1 "SELECT * FROM sel_city('msk WHERE false
        UNION ALL
        SELECT usename FROM pg_user
        UNION ALL
        SELECT name FROM city_msk', '');"

###############################################################################

stop_here
cleanup
demo_end
