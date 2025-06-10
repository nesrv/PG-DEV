#!/bin/bash

. ../lib

init

start_here ...

###############################################################################
h '1. Человеко-часы'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Таблица с производственными сменами:'

s 1 "CREATE TABLE shifts (
    employee_name text,
    work_hours tstzrange
);"

c 'Добавим несколько записей (рабочий день с перерывом на обед):'

s 1 "INSERT INTO shifts VALUES
    ('alice',   '[2020-04-01 09:00,2020-04-01 13:00)'),
    ('alice',   '[2020-04-01 14:00,2020-04-01 18:00)'),
    ('bob',     '[2020-04-01 10:00,2020-04-01 14:00)'),
    ('bob',     '[2020-04-01 15:00,2020-04-01 17:00)'),
    ('charlie', '[2020-04-01 08:30,2020-04-01 12:30)'),
    ('charlie', '[2020-04-01 13:30,2020-04-01 17:30)');"

c 'Результат:'

s 1 "WITH intersection(r) AS (
    SELECT work_hours * '[2020-04-01 09:50,2020-04-01 10:05)'::tstzrange
    FROM shifts
)
SELECT sum(upper(r) - lower(r))
FROM intersection;"

###############################################################################
h '2. Блокировки при добавлении значения'

c 'Тип перечисления и таблица:'

s 1 "CREATE TYPE statuses AS ENUM ('todo', 'done');"

s 1 "CREATE TABLE process (
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    status statuses
);"
s 1 "INSERT INTO process(status)
    SELECT 'todo' FROM generate_series(1,1_000_000);"

c 'Начинаем транзакцию:'

s 1 "BEGIN;"

s 1 '\timing on'
s 1 "ALTER TYPE statuses ADD VALUE 'in progress';"
s 1 '\timing off'

c 'Выведем только блокировки таблицы:'

s 1 "SELECT relation::regclass, mode
FROM pg_locks
WHERE relation = 'process'::regclass;"

s 1 "COMMIT;"

c 'Итак:'
ul 'добавление выполняется быстро;'
ul 'таблица не блокируется.'

p

c 'Вариант с проверкой CHECK.'

s 1 "DROP TABLE process;"
s 1 "DROP TYPE statuses;"
s 1 "CREATE TABLE process (
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    status text CHECK (status IN ('todo','done'))
);"
s 1 "INSERT INTO process(status)
    SELECT 'todo' FROM generate_series(1,1_000_000);"

s 1 "BEGIN;"

s 1 '\timing on'
s 1 "ALTER TABLE process
    DROP CONSTRAINT process_status_check,
    ADD CHECK (status IN ('todo','done','in progress'));"
s 1 '\timing off'

s 1 "SELECT relation::regclass, mode
FROM pg_locks
WHERE relation = 'process'::regclass;"

s 1 "COMMIT;"

c 'Здесь:'
ul 'добавление выполняется дольше — поскольку требуется перепроверка всех значений в таблице;'
ul 'таблица полностью блокируется на время изменения ограничения.'

c 'Это плохой вариант.'

p

c 'Вариант с проверкой на домене.'

s 1 "DROP TABLE process;"
s 1 "CREATE DOMAIN statuses AS text CHECK (VALUE IN ('todo','done'));"
s 1 "CREATE TABLE process (
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    status statuses
);"
s 1 "INSERT INTO process(status)
    SELECT 'todo' FROM generate_series(1,1_000_000);"

s 1 "BEGIN;"

s 1 '\timing on'
s 1 "ALTER DOMAIN statuses
    DROP CONSTRAINT statuses_check;"
s 1 "ALTER DOMAIN statuses
    ADD CHECK (VALUE IN ('todo','done','in progress'));"
s 1 '\timing off'

s 1 "SELECT relation::regclass, mode
FROM pg_locks
WHERE relation = 'process'::regclass;"

s 1 "COMMIT;"

c 'В этом случае:'
ul 'изменение также выполняется долго;'
ul 'таблица блокируется в более мягком режиме (конфликтует с изменением данных, но разрешает чтение).'

c 'Это вариант несколько лучше, чем CHECK.'

###############################################################################

stop_here
cleanup
