#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Роли и таблицы'

s 1 'CREATE DATABASE access_rls;'
s 1 '\c access_rls'

PSQL_PROMPT1='student=# '
s 1 'CREATE ROLE alice LOGIN;'
s 1 'CREATE ROLE bob LOGIN;'
s 1 'CREATE ROLE charlie LOGIN;'

s 1 'CREATE TABLE users_depts(
  login text,
  department text
);'
s 1 "INSERT INTO users_depts VALUES 
  ('alice',  'PR'),
  ('bob',    'Sales'),
  ('charlie','PR'),
  ('charlie','Sales');"

s 1 'CREATE TABLE revenue(
  department text,
  amount numeric(10,2)
);'
s 1 "INSERT INTO revenue SELECT 'PR',   -random()* 100.00 FROM generate_series(1,100000);"
s 1 "INSERT INTO revenue SELECT 'Sales', random()*1000.00 FROM generate_series(1,10000);"

###############################################################################
h '2. Политики и привилегии'

s 1 'CREATE POLICY departments ON revenue
  USING (department IN (SELECT department FROM users_depts WHERE login = current_user));'

s 1 'CREATE POLICY amount ON revenue AS RESTRICTIVE
  USING (true)
  WITH CHECK (
    (SELECT count(*) FROM users_depts WHERE login = current_user) > 1
    OR abs(amount) <= 100.00
  );'

s 1 'ALTER TABLE revenue ENABLE ROW LEVEL SECURITY;'

s 1 'GRANT SELECT ON users_depts TO alice, bob, charlie;'
s 1 'GRANT SELECT, INSERT ON revenue TO alice, bob, charlie;'

###############################################################################
h '3. Проверка'

c 'Алиса:'

s 1 '\c - alice'
PSQL_PROMPT1='alice=> '
s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'
s 1 "INSERT INTO revenue VALUES ('PR', 100.00);"
s 1 "INSERT INTO revenue VALUES ('PR', 101.00);"

c 'Боб:'

s 1 '\c - bob'
PSQL_PROMPT1='bob=> '
s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'
s 1 "INSERT INTO revenue VALUES ('Sales', 100.00);"
s 1 "INSERT INTO revenue VALUES ('Sales', 101.00);"

c 'Чарли:'

s 1 '\c - charlie'
PSQL_PROMPT1='charlie=> '
s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'
s 1 "INSERT INTO revenue VALUES ('PR', 1000.00);"
s 1 "INSERT INTO revenue VALUES ('Sales', 1000.00);"

###############################################################################
h '4. Накладные расходы'

c 'Выполним запрос несколько раз, чтобы оценить среднее значение времени выполнения.'

s 1 '\timing on'

c 'Сначала от имени charlie:'

s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'
s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'
s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'

c 'А теперь от имени владельца таблицы, на которого по умолчанию политики не действуют:'

s 1 '\c - student'
PSQL_PROMPT1='student=# '
s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'
s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'
s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'

c 'В данном конкретном случае накладные расходы не драматичны, хотя и вполне ощутимы.'

stop_here

###############################################################################
psql_close 1
