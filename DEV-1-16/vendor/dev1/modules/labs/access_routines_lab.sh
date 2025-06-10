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

c 'Каждый сотрудник имеет уникальный логин. Совмещение допускается.'
s 1 'CREATE TABLE users_depts(
  login text,
  department text
);'

c 'Таблица приложения для учета доходов и расходов.'
s 1 'CREATE TABLE revenue(
  department text,
  amount numeric(10,2)
);'

p

###############################################################################
h '2. Создание ролей'

c 'Групповая роль emp.'
s 1 'CREATE ROLE emp;'

c 'Роли для пользователей приложения.'
s 1 'CREATE ROLE alice LOGIN IN ROLE emp;'
s 1 'CREATE ROLE bob LOGIN IN ROLE emp;'
s 1 'CREATE ROLE charlie LOGIN IN ROLE emp;'

s 1 "GRANT CREATE,USAGE ON SCHEMA app TO emp;"
s 1 "GRANT INSERT ON revenue TO emp;"

s 1 "INSERT INTO users_depts VALUES 
	('alice','PR'), ('bob','Sales'), 
	('charlie', 'PR'), ('charlie', 'Sales');"

c 'Заполним таблицу доходов/расходов.'
s 1 "INSERT INTO revenue SELECT 'PR',   -random() * 100.00 FROM generate_series(1, 2);"
s 1 "INSERT INTO revenue SELECT 'Sales', random() * 500.00 FROM generate_series(1, 2);"

p

###############################################################################
h '3. Представление.'

s 1 "CREATE VIEW vrevenue AS
        SELECT * FROM revenue WHERE department IN
        (SELECT department FROM users_depts WHERE login = session_user);"

s 1 "GRANT SELECT ON vrevenue TO emp;"

p

c 'Проверим фильтрацию строк.'
s 1 "SELECT * FROM vrevenue;"
c 'В сеансе student - он не имеет логина.'

c 'Чарли должен видеть все строки.'
s 1 '\c - charlie'
PSQL_PROMPT1='charlie=> '
s 1 "SELECT * FROM vrevenue;"

c 'Боб - только доходы.'
s 1 '\c - bob'
PSQL_PROMPT1='bob=> '
s 1 "SELECT * FROM vrevenue;"

c 'Алиса - только расходы.'
s 1 '\c - alice'
PSQL_PROMPT1='alice=> '
s 1 "SELECT * FROM vrevenue;"

p

###############################################################################
h '4. Нарушение безопасности.'

c 'Создадим функцию для нарушения защиты строк.'
s 1 "CREATE FUNCTION penetrate(text, numeric) RETURNS bool AS
\$\$
BEGIN
        RAISE NOTICE 'Dept % amount %', \$1, \$2;
        RETURN true;
        END;
\$\$
LANGUAGE plpgsql COST 0.0000000000000000000001;"

c 'Нарушим защиту.'
s 1 "SELECT * FROM vrevenue WHERE penetrate(department, amount);"
c 'Функция допускает утечку информации.'

p

stop_here

psql_close 1

