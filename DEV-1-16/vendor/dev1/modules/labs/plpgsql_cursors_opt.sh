#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Распределение расходов'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Таблица:'

s 1 "CREATE TABLE depts(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    employees integer,
    expenses numeric(10,2)
);"
s 1 "INSERT INTO depts(employees) VALUES (20),(10),(30);"

c 'Функция:'

s 1 "CREATE FUNCTION distribute_expenses(amount numeric) RETURNS void 
AS \$\$
DECLARE
    depts_cur CURSOR FOR
        SELECT employees FROM depts FOR UPDATE;
    total_employees numeric;
    expense numeric;
    rounding_err numeric := 0.0;
    cent numeric;
BEGIN
    SELECT sum(employees) FROM depts INTO total_employees;
    FOR dept IN depts_cur LOOP
        expense := amount * (dept.employees / total_employees);
        rounding_err := rounding_err + (expense - round(expense,2));

        cent := round(rounding_err,2);
        expense := expense + cent;
        rounding_err := rounding_err - cent;

        UPDATE depts SET expenses = round(expense,2)
        WHERE CURRENT OF depts_cur;
    END LOOP;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Проверка:'

s 1 "SELECT distribute_expenses(100.0);"
s 1 "SELECT * FROM depts;"

c 'Разумеется, возможны и другие алгоритмы, например, перенос всех ошибок округления на одну строку и т. п.'
c 'В курсе DEV2 рассматривается другое решение этой задачи с помощью пользовательских агрегатных функций.'

###############################################################################
h '2. Слияние отсортированных наборов'

c 'Эта реализация предполагает, что числа не могут иметь неопределенные значения NULL.'

s 1 "CREATE FUNCTION merge(c1 refcursor, c2 refcursor)
RETURNS SETOF integer 
AS \$\$
DECLARE
    a integer;
    b integer;
BEGIN
    FETCH c1 INTO a;
    FETCH c2 INTO b;
    LOOP
        EXIT WHEN a IS NULL AND b IS NULL;
        IF a < b OR b IS NULL THEN
            RETURN NEXT a;
            FETCH c1 INTO a;
        ELSE
            RETURN NEXT b;
            FETCH c2 INTO b;
        END IF;
    END LOOP;
END
\$\$ VOLATILE LANGUAGE plpgsql;"

c 'Проверяем.'

s 1 "BEGIN;"
s 1 "DECLARE c1 CURSOR FOR
    SELECT * FROM (VALUES (1),(3),(5));"
s 1 "DECLARE c2 CURSOR FOR
    SELECT * FROM (VALUES (2),(3),(4));"
s 1 "SELECT * FROM merge('c1','c2');"
s 1 "COMMIT;"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
