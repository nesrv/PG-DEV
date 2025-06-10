#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Случайная временнáя отметка'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Функция с двумя временными отметками:'

s 1 "CREATE FUNCTION rnd_timestamp(t_start timestamptz, t_end timestamptz)
RETURNS timestamptz
LANGUAGE sql VOLATILE
RETURN t_start + (t_end - t_start) * random();"


c 'Категория изменчивости — volatile. Используется функция random, поэтому функция будет возвращать разные значения при одних и тех же входных параметрах.'

s 1 "SELECT current_timestamp,
    rnd_timestamp(
        current_timestamp,
        current_timestamp + interval '1 hour'
    )
FROM generate_series(1,10);"

c 'Вторую функцию (с параметром-интервалом) можно определить через первую:'

s 1 "CREATE FUNCTION rnd_timestamp(t_start timestamptz, t_delta interval)
RETURNS timestamptz
LANGUAGE sql VOLATILE 
RETURN rnd_timestamp(t_start, t_start + t_delta);"


s 1 "SELECT rnd_timestamp(current_timestamp, interval '1 hour');"

###############################################################################
h '2. Автомобильные номера'

c 'Создадим таблицу с номерами.'

s 1 "CREATE TABLE cars(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    regnum text
);"
s 1 "INSERT INTO cars(regnum) VALUES
    ('К 123 ХМ'), ('k123xm'), ('A 098BC');"

c 'Функция нормализации:'

s 1 "CREATE FUNCTION to_normal(regnum text) RETURNS text
LANGUAGE sql IMMUTABLE 
RETURN upper(translate(regnum, 'АВЕКМНОРСТУХ ', 'ABEKMHOPCTYX'));"


c 'Категория изменчивости — immutable. Функция всегда возвращает одинаковое значение при одних и тех же входных параметрах.'

s 1 "SELECT to_normal(regnum) FROM cars;"

c 'Теперь легко исключить дубликаты:'

s 1 "CREATE FUNCTION num_unique() RETURNS bigint
LANGUAGE sql STABLE
RETURN (
SELECT count(DISTINCT to_normal(regnum))
FROM cars
);"


s 1 "SELECT num_unique();"

###############################################################################
h '3. Корни квадратного уравнения'

s 1 "CREATE FUNCTION square_roots(
    a float, 
    b float, 
    c float, 
    x1 OUT float, 
    x2 OUT float
)
LANGUAGE sql IMMUTABLE
RETURN (
WITH discriminant(d) AS (
    SELECT b*b - 4*a*c
)
SELECT (CASE WHEN d >= 0.0 THEN (-b + sqrt(d))/2/a END,
        CASE WHEN d >  0.0 THEN (-b - sqrt(d))/2/a END)
FROM discriminant
);"

c 'Категория изменчивости — immutable. Функция всегда возвращает одинаковое значение при одних и тех же входных параметрах.'

s 1 "SELECT square_roots(1,  0, -4);"
s 1 "SELECT square_roots(1, -4,  4);"
s 1 "SELECT square_roots(1,  1,  1);"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
