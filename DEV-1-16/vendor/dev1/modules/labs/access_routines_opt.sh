#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. База данных, схема, таблицы.'

PSQL_PROMPT1='student=# '

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Схема для объектов приложения. Настроим путь поиска и предоставим права на схему ролям.'
s 1 "CREATE SCHEMA app;"
s 1 "ALTER DATABASE $TOPIC_DB SET search_path TO app, public;"
s 1 '\c'

c 'Таблицы.'
s 1 'CREATE TABLE users_depts(
  login text,
  department text
);'

s 1 'CREATE TABLE revenue(
  department text,
  amount numeric(10,2)
);'

p

###############################################################################
h '2. Создание роли'

s 1 'CREATE ROLE alice LOGIN;'

s 1 "GRANT CREATE,USAGE ON SCHEMA app TO alice;"
s 1 "GRANT INSERT ON revenue TO alice;"

s 1 "INSERT INTO users_depts VALUES ('alice','PR'), ('bob','Sales');"

c 'Доходы/расходы.'
s 1 "INSERT INTO revenue SELECT 'PR',   -random() * 100.00 FROM generate_series(1, 2);"
s 1 "INSERT INTO revenue SELECT 'Sales', random() * 500.00 FROM generate_series(1, 2);"

p

###############################################################################
h '3. Представление.'

s 1 "CREATE VIEW vrevenue AS
        SELECT * FROM revenue WHERE department IN
        (SELECT department FROM users_depts WHERE login = session_user);"

s 1 "GRANT SELECT ON vrevenue TO alice;"

p

c 'Проверим фильтрацию строк.'
psql_open A 2 -d $TOPIC_DB -U alice
PSQL_PROMPT2='alice=> '
s 2 "SELECT * FROM vrevenue;"

c 'Создадим функцию для нарушения защиты строк.'
s 2 "CREATE FUNCTION penetrate(text, numeric) RETURNS bool AS
\$\$
BEGIN
        RAISE NOTICE 'Dept % amount %', \$1, \$2;
        RETURN true;
        END;
\$\$
LANGUAGE plpgsql COST 0.0000000000000000000001;"

p

###############################################################################
h '4. Барьер безопасности.'

c 'План запроса без барьера безопасности.'
s 2 "EXPLAIN ANALYZE SELECT * FROM vrevenue WHERE penetrate(department, amount);"
c 'Функция допускает утечку информации.'

c 'Администратор устанавливает барьер безопасности.'
s 1 "ALTER VIEW vrevenue SET (security_barrier);"

c 'Проверим план запроса теперь.'
s 2 "EXPLAIN ANALYZE SELECT * FROM vrevenue WHERE penetrate(department, amount);"
c 'Сначала фильтруются строки. Затем производятся все остальные действия. Утечки нет.'

p

stop_here

psql_close 1

