#!/bin/bash

. ../lib

init

start_here ...

###############################################################################
h '1. Превышение числа фоновых процессов'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE EXTENSION pg_background;"

c 'Уменьшим значение параметра-ограничителя до 2, учитывая, что один фоновый процесс (logical replication launcher) запускается системой автоматически. Изменение требует рестарта сервера.'

s 1 "ALTER SYSTEM SET max_worker_processes = 2;"
pgctl_restart A

sleep 1

psql_open A 1 $TOPIC_DB

s 1 "SHOW max_worker_processes;"

c 'Запустим один длительный фоновый процесс:'

s 1 "SELECT * FROM pg_background_launch(
    'SELECT pg_sleep(10)'
);"

c 'Теперь попробуем запустить еще один, перехватывая исключение:'

si 1 "DO \$\$
DECLARE
    hint text;
BEGIN
    PERFORM pg_background_launch('SELECT 42');
EXCEPTION
    WHEN others THEN
        GET STACKED DIAGNOSTICS hint := PG_EXCEPTION_HINT;
        RAISE NOTICE E'sqlstate = %\\nsqlerrm = %\\nhint = %',
            SQLSTATE, SQLERRM, hint;
END;
\$\$;"

c 'Ошибка с кодом 53000 относится к группе insufficient_resources.'
c 'Функция может выглядеть следующим образом:'

s 1 "CREATE FUNCTION try_background_launch(sql text, retries integer)
RETURNS integer
AS \$\$
DECLARE
BEGIN
    LOOP
        BEGIN
            RETURN pg_background_launch(sql);
        EXCEPTION
            WHEN insufficient_resources THEN
                IF retries > 0 THEN
                    retries := retries - 1;
                    RAISE NOTICE 'Sleeping for 1 sec, % retries left',
                        retries;
                    PERFORM pg_sleep(1);
                ELSE
                    RAISE;
                END IF;
        END;
    END LOOP;
END
\$\$ LANGUAGE plpgsql VOLATILE;"

wait_sql 1 "select count(*)=0 FROM pg_stat_activity where backend_type='pg_background';"

c 'Проверим:'

s 1 "SELECT * FROM pg_background_launch(
    'SELECT pg_sleep(10)'
);"

si 1 "SELECT * FROM pg_background_result(try_background_launch(
    'SELECT 42', 15
)) AS (result integer);"

c 'Восстановим значение параметра по умолчанию:'

s 1 "ALTER SYSTEM RESET ALL;"
pgctl_restart A

###############################################################################
h '2. Сравнение dblink и pg_background'

psql_open A 1 $TOPIC_DB

s 1 "CREATE EXTENSION dblink;"

s 1 '\timing on'

c 'Просто запрос (выполняем с помощью динамического SQL, чтобы исключить кеширование плана запроса):'

s 1 "DO \$\$
DECLARE
    result integer;
BEGIN
    FOR i IN 1 .. 1000 LOOP
        EXECUTE 'SELECT 1' INTO result;
    END LOOP;
END;
\$\$;"

c 'Расширение pg_background:'

s 1 "DO \$\$
DECLARE
    result integer;
BEGIN
    FOR i IN 1 .. 1000 LOOP
        SELECT * INTO result FROM pg_background_result(
            pg_background_launch('SELECT 1')
        ) AS (result integer);
    END LOOP;
END;
\$\$;"

c 'Расширение dblink:'

s 1 "DO \$\$
DECLARE
    result integer;
BEGIN
    FOR i IN 1 .. 1000 LOOP
        SELECT * INTO result FROM dblink(
            'host=localhost port=5432 dbname=postgres user=postgres password=postgres',
            'SELECT 1'
        ) AS (result integer);
    END LOOP;
END;
\$\$;"

###############################################################################

stop_here
cleanup
