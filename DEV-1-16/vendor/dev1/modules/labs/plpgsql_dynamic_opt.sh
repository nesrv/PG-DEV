#!/bin/bash

. ../lib

init

start_here

###############################################################################
h 'Получение матричного отчета'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Вспомогательная функция для формирования текста динамического запроса:'

s 1 "CREATE FUNCTION form_query() RETURNS text
AS \$\$
DECLARE
    query_text text;
    columns text := '';
    r record;
BEGIN
    -- Статическая часть запроса.
    -- Первые два столбца: имя схемы и общее количество функций в ней
    query_text :=
\$query\$
SELECT pronamespace::regnamespace::text AS schema
     , count(*) AS total{{columns}}
FROM pg_proc
GROUP BY pronamespace::regnamespace
ORDER BY schema
\$query\$;

    -- Динамическая часть запроса.
    -- Получаем список владельцев функций, для каждого — отдельный столбец
    FOR r IN SELECT DISTINCT proowner AS owner FROM pg_proc ORDER BY 1
    LOOP
        columns := columns || format(
            E'\\n     , sum(CASE WHEN proowner = %s THEN 1 ELSE 0 END) AS %I',
            r.owner,
            r.owner::regrole
        );
    END LOOP;

    RETURN replace(query_text, '{{columns}}', columns);
END
\$\$ STABLE LANGUAGE plpgsql;"

c 'Итоговый текст запроса:'

s 1 "SELECT form_query();"

c 'Теперь создаем функцию для матричного отчета:'

s 1 "CREATE FUNCTION matrix() RETURNS SETOF record
AS \$\$
BEGIN
    RETURN QUERY EXECUTE form_query();
END
\$\$ STABLE LANGUAGE plpgsql;"

c 'Простое выполнение запроса приведет к ошибке, так как не указана структура возвращаемых записей:'

s 1 "SELECT * FROM matrix();"

c 'В этом состоит важное ограничение на использование функций, возвращающих произвольную выборку. В момент вызова необходимо знать и указать структуру возвращаемой записи.'
c 'В общем случае структура возвращаемой записи может быть неизвестна, но, применительно к нашему матричному отчету, можно выполнить еще один запрос, который покажет, как правильно вызвать функцию matrix.'

c 'Подготовим текст запроса:'

s 1 "CREATE FUNCTION matrix_call() RETURNS text
AS \$\$
DECLARE
    cmd text;
    r record;
BEGIN
    cmd := 'SELECT * FROM matrix() AS (
    schema text, total bigint';

    FOR r IN SELECT DISTINCT proowner AS owner FROM pg_proc ORDER BY 1
    LOOP
        cmd := cmd || format(', %I bigint', r.owner::regrole::text);
    END LOOP;
    cmd := cmd || E'\n)';

    RAISE NOTICE '%', cmd;
    RETURN cmd;
END
\$\$ STABLE LANGUAGE plpgsql;"

c 'Теперь мы можем вызовом martix_call получить запрос, отражающий структуру матричного отчета, а затем выполнить этот запрос и получить отчет (psql позволяет все это сделать одной командой \gexec):'

s 1 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
s 1 "SELECT matrix_call() \gexec"
s 1 "COMMIT;"

c 'Матричный отчет корректно формируется.'

ul 'Уровень изоляции Repeatable Read гарантирует, что отчет сформируется, даже если между двумя запросами появится функция у нового владельца.'
ul 'Можно было бы и напрямую выполнить запрос, возвращаемый функцией form_query. Но задача получить в клиентском приложении список возвращаемых столбцов все равно останется. Функция matrix_call показывает, как ее можно решить дополнительным запросом.'

c 'Еще один вариант решения заключается в том, чтобы вместо набора записей произвольной структуры возвращать набор строк слабоструктурированного типа (такого, как JSON или XML). Эти типы рассматриваются в курсе DEV2.'

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
