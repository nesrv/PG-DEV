#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Трассировка с помощью plpgsql_check'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Загрузим расширение (в данном случае устанавливать его в базу данных командой CREATE EXTENSION не нужно):'

s 1 "LOAD 'plpgsql_check';"

c 'Включим трассировку:'

s 1 "SET plpgsql_check.enable_tracer = on;"
s 1 "SET plpgsql_check.tracer = on;"

c 'Несколько функций, вызывающих друг друга:'

s 1 "CREATE FUNCTION foo(n integer) RETURNS integer
AS \$\$
BEGIN
    RETURN bar(n-1);
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE FUNCTION bar(n integer) RETURNS integer
AS \$\$
BEGIN
    RETURN baz(n-1);
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE FUNCTION baz(n integer) RETURNS integer
AS \$\$
BEGIN
    RETURN n;
END
\$\$ LANGUAGE plpgsql;"

c 'Пример работы трассировки:'

s 1 "SELECT foo(3);"

c 'Выводятся не только события начала и окончания работы функций, но и значения параметров, а также затраченное на выполнение время (в расширении есть и возможность профилирования, которую мы не рассматриваем).'

c 'Выключим трассировку:'

s 1 "SET plpgsql_check.tracer = off;"

###############################################################################
h '2. Имя функции в отладочных сообщениях'

c 'Напишем процедуру, которая выводит верхушку стека вызовов (за исключением самой процедуры трассировки). Сообщение выводится с отступом, который соответствует глубине стека.'

s 1 "CREATE PROCEDURE raise_msg(msg text)
AS \$\$
DECLARE
    ctx text;
    stack text[];
BEGIN
    GET DIAGNOSTICS ctx := PG_CONTEXT;
    stack := regexp_split_to_array(ctx, E'\n');
    RAISE NOTICE '%: %',
        repeat('. ', array_length(stack,1)-2) || stack[3], msg;
END
\$\$ LANGUAGE plpgsql;"

c 'Пример работы трассировки:'

s 1 "CREATE TABLE t(n integer);"
s 1 "CREATE FUNCTION on_insert() RETURNS trigger
AS \$\$
BEGIN
    CALL raise_msg('NEW = '||NEW::text);
    RETURN NEW;
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE TRIGGER t_before_row
BEFORE INSERT ON t
FOR EACH ROW
EXECUTE FUNCTION on_insert();"

s 1 "CREATE PROCEDURE insert_into_t()
AS \$\$
BEGIN
    CALL raise_msg('start');
    INSERT INTO t SELECT id FROM generate_series(1,3) id;
    CALL raise_msg('end');
END
\$\$ LANGUAGE plpgsql;"

s 1 "CALL insert_into_t();"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
