#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Функция map'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE FUNCTION map(a INOUT float[], func text)
AS \$\$
DECLARE
    i integer;
    x float;
BEGIN
    IF cardinality(a) > 0 THEN
        FOR i IN array_lower(a,1)..array_upper(a,1) LOOP
            EXECUTE format('SELECT %I(\$1)',func) USING a[i] INTO x;
            a[i] := x;
        END LOOP;
    END IF;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

ul 'INTO a[i] не работает, поэтому нужна отдельная переменная.'

s 1 "SELECT map(ARRAY[4.0,9.0,16.0],'sqrt');"
s 1 "SELECT map(ARRAY[]::float[],'sqrt');"

c 'Другой вариант реализации с циклом FOREACH:'

s 1 "CREATE OR REPLACE FUNCTION map(a float[], func text) RETURNS float[]
AS \$\$
DECLARE
    x float;
    b float[]; -- пустой массив
BEGIN
    FOREACH x IN ARRAY a LOOP
        EXECUTE format('SELECT %I(\$1)',func) USING x INTO x;
        b := b || x;
    END LOOP;
    RETURN b;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

s 1 "SELECT map(ARRAY[4.0,9.0,16.0],'sqrt');"
s 1 "SELECT map(ARRAY[]::float[],'sqrt');"

###############################################################################
h '2. Функция reduce'

s 1 "CREATE FUNCTION reduce(a float[], func text) RETURNS float
AS \$\$
DECLARE
    i integer;
    r float := NULL;
BEGIN
    IF cardinality(a) > 0 THEN
        r := a[array_lower(a,1)];
        FOR i IN array_lower(a,1)+1 .. array_upper(a,1) LOOP
            EXECUTE format('SELECT %I(\$1,\$2)',func) USING r, a[i]
                INTO r;
        END LOOP;
    END IF;
    RETURN r;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

c 'Greatest (как и least) — не функция, а встроенное условное выражение, поэтому из-за экранирования не получится использовать ее напрямую:'

s 1 "SELECT reduce( ARRAY[1.0,3.0,2.0], 'greatest');"

c 'Вместо нее используем реализованную в демонстрации функцию maximum.'

s 1 "CREATE FUNCTION maximum(VARIADIC a anycompatiblearray, maxsofar OUT anycompatible)
AS \$\$
DECLARE
    x maxsofar%TYPE;
BEGIN
    FOREACH x IN ARRAY a LOOP
        IF x IS NOT NULL AND (maxsofar IS NULL OR x > maxsofar) THEN
            maxsofar := x;
        END IF;
    END LOOP;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

s 1 "SELECT reduce(ARRAY[1.0,3.0,2.0], 'maximum');"
s 1 "SELECT reduce(ARRAY[1.0], 'maximum');"
s 1 "SELECT reduce(ARRAY[]::float[], 'maximum');"

c 'Вариант с циклом FOREACH:'

s 1 "CREATE OR REPLACE FUNCTION reduce(a float[], func text) RETURNS float
AS \$\$
DECLARE
    x float;
    r float;
    first boolean := true;
BEGIN
    FOREACH x IN ARRAY a LOOP
        IF first THEN
            r := x;
            first := false;
        ELSE
            EXECUTE format('SELECT %I(\$1,\$2)',func) USING r, x INTO r;
        END IF;
    END LOOP;
    RETURN r;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

s 1 "SELECT reduce(ARRAY[1.0,3.0,2.0], 'maximum');"
s 1 "SELECT reduce(ARRAY[1.0], 'maximum');"
s 1 "SELECT reduce(ARRAY[]::float[], 'maximum');"

###############################################################################
h '3. Полиморфные варианты функций'

c 'Функция map.'

s 1 "DROP FUNCTION map(float[],text);"

s 1 "CREATE FUNCTION map(
    a anyarray,
    func text,
    elem anyelement DEFAULT NULL
)
RETURNS anyarray
AS \$\$
DECLARE
    x elem%TYPE;
    b a%TYPE;
BEGIN
    FOREACH x IN ARRAY a LOOP
        EXECUTE format('SELECT %I(\$1)',func) USING x INTO x;
        b := b || x;
    END LOOP;
    RETURN b;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

ul 'Требуется фиктивный параметр типа anyelement, чтобы внутри функции объявить переменную такого же типа.'

s 1 "SELECT map(ARRAY[4.0,9.0,16.0],'sqrt');"
s 1 "SELECT map(ARRAY[]::float[],'sqrt');"

c 'Пример вызова с другим типом данных:'

s 1 "SELECT map(ARRAY[' a ','  b','c  '],'btrim');"

p

c 'Функция reduce.'

s 1 "DROP FUNCTION reduce(float[],text);"

s 1 "CREATE FUNCTION reduce(
    a anyarray,
    func text,
    elem anyelement DEFAULT NULL
)
RETURNS anyelement
AS \$\$
DECLARE
    x elem%TYPE;
    r elem%TYPE;
    first boolean := true;
BEGIN
    FOREACH x IN ARRAY a LOOP
        IF first THEN
            r := x;
            first := false;
        ELSE
            EXECUTE format('SELECT %I(\$1,\$2)',func) USING r, x INTO r;
        END IF;
    END LOOP;
    RETURN r;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

s 1 "CREATE FUNCTION add(x anyelement, y anyelement) RETURNS anyelement
AS \$\$
BEGIN
    RETURN x + y;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

s 1 "SELECT reduce(ARRAY[1,-2,4], 'add');"
s 1 "SELECT reduce(ARRAY['a','b','c'], 'concat');"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
