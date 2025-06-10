#!/bin/bash

. ../lib

init

start_here ...

###############################################################################
h '1. Формирование JSON'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Создадим таблицы и тестовые данные:'

s 1 "CREATE TABLE users(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name text
);"
s 1 "CREATE TABLE orders(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    user_id integer REFERENCES users(id),
    amount numeric
);"
s 1 "INSERT INTO users(name) VALUES ('alice'), ('bob'), ('charlie');"
s 1 "INSERT INTO orders(amount, user_id)
    SELECT round( (random()*1000)::numeric, 2), u.id
    FROM users u, generate_series(1,3);"

c 'Функция использует jsonb_build_object для создания объекта и jsonb_agg для создания массива:'

s 1 "CREATE FUNCTION get_users_w_orders(user_id integer) RETURNS jsonb
LANGUAGE sql STABLE
RETURN (SELECT jsonb_build_object(
    'user_id', u.id,
    'name',    u.name,
    'orders',  jsonb_agg(jsonb_build_object(
        'order_id', o.id,
        'amount',   o.amount
    ))
)
FROM users u
    JOIN orders o ON o.user_id = u.id
WHERE u.id = get_users_w_orders.user_id
GROUP BY u.id);"

c 'Проверим:'

s 1 "SELECT jsonb_pretty(get_users_w_orders(1));"

###############################################################################
h '2. Хранение переводов'

c 'Таблица с городами:'

s 1 "CREATE TABLE cities_ml(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    data jsonb
);"
s 1 "INSERT INTO cities_ml(data) VALUES
    ('{ \"ru\": \"Москва\",
        \"en\": \"Moscow\",
        \"it\": \"Mosca\" }'),
    ('{ \"ru\": \"Санкт-Петербург\",
        \"en\": \"Saint Petersburg\",
        \"it\": \"San Pietroburgo\" }');"

c 'Представление может быть устроено следующим образом:'

s 1 "CREATE VIEW cities AS
SELECT c.id,
       c.data ->> current_setting(
                      'translation.lang', /* missing_ok */true
                  ) AS name
FROM cities_ml c;"

c 'Проверим результат с разными значениями параметра:'

s 1 "SET translation.lang = 'ru';"
s 1 "SELECT * FROM cities;"
s 1 "SET translation.lang = 'en';"
s 1 "SELECT * FROM cities;"

c 'Таким образом приложение может установить язык один раз в начале сеанса, и затем запросы не будут зависеть от выбора пользователя.'

###############################################################################

stop_here
cleanup
