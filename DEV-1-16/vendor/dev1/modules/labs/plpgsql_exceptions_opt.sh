#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Try-catch-finally'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Сложность состоит в том, что операторы finally должны выполняться всегда, даже в случае возникновения ошибки в операторах catch (блок EXCEPTION).'
c 'Решение может использовать два вложенных блока и фиктивное исключение, которое вызывается при нормальном завершении внутреннего блока. Это дает возможность поместить операторы finally в одно место — обработчик ошибок внешнего блока.'

s 1 "DO \$\$
BEGIN
    BEGIN
        RAISE NOTICE 'Операторы try';
        --
        RAISE NOTICE '...нет исключения';
    EXCEPTION
        WHEN no_data_found THEN
            RAISE NOTICE 'Операторы catch';
    END;
    RAISE SQLSTATE 'ALLOK'; 
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Операторы finally';
        IF SQLSTATE != 'ALLOK' THEN
            RAISE;
        END IF;
END
\$\$;"

s 1 "DO \$\$
BEGIN
    BEGIN
        RAISE NOTICE 'Операторы try';
        --
        RAISE NOTICE '...исключение, которое обрабатывается';
        RAISE no_data_found;
    EXCEPTION
        WHEN no_data_found THEN
            RAISE NOTICE 'Операторы catch';
    END;
    RAISE SQLSTATE 'ALLOK'; 
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Операторы finally';
        IF SQLSTATE != 'ALLOK' THEN
            RAISE;
        END IF;
END
\$\$;"

s 1 "DO \$\$
BEGIN
    BEGIN
        RAISE NOTICE 'Операторы try';
        --
        RAISE NOTICE '...исключение, которое не обрабатывается';
        RAISE division_by_zero;
    EXCEPTION
        WHEN no_data_found THEN
            RAISE NOTICE 'Операторы catch';
    END;
    RAISE SQLSTATE 'ALLOK'; 
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Операторы finally';
        IF SQLSTATE != 'ALLOK' THEN
            RAISE;
        END IF;
END
\$\$;"

c 'Но в предложенном решении всегда происходит откат всех изменений, выполненных в блоке, поэтому оно не годится для команд, изменяющих состояние базы данных. Также не стоит забывать о накладных расходах на обработку исключений: это задание — не более, чем просто упражнение.'

###############################################################################
h '2. GET DIAGNOSTICS'

s 1 "DO \$\$
DECLARE
    ctx text;
BEGIN
    RAISE division_by_zero;                       -- line 5
EXCEPTION
    WHEN others THEN
        GET STACKED DIAGNOSTICS ctx := PG_EXCEPTION_CONTEXT;
        RAISE NOTICE E'stacked =\n%', ctx;
        GET CURRENT DIAGNOSTICS ctx := PG_CONTEXT; -- line 10
        RAISE NOTICE E'current =\n%', ctx;
END
\$\$;"

c 'GET STACKED DIAGNOSTICS дает стек вызовов, приведший к ошибке.'
c 'GET [CURRENT] DIAGNOSTICS дает текущий стек вызовов.'

###############################################################################
h '3. Стек вызовов как массив'

c 'Собственно функция:'

s 1 "CREATE FUNCTION getstack() RETURNS text[]
AS \$\$
DECLARE
    ctx text;
BEGIN
    GET DIAGNOSTICS ctx := PG_CONTEXT;
    RETURN (regexp_split_to_array(ctx, E'\n'))[2:];
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Чтобы проверить ее работу, создадим несколько функций, которые вызывают друг друга:'

s 1 "CREATE FUNCTION foo() RETURNS integer
AS \$\$
BEGIN
    RETURN bar();
END
\$\$ VOLATILE LANGUAGE plpgsql;"

s 1 "CREATE FUNCTION bar() RETURNS integer
AS \$\$
BEGIN
    RETURN baz();
END
\$\$ VOLATILE LANGUAGE plpgsql;"

s 1 "CREATE FUNCTION baz() RETURNS integer
AS \$\$
BEGIN
    RAISE NOTICE '%', getstack();
    RETURN 0;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

s 1 "SELECT foo();"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
