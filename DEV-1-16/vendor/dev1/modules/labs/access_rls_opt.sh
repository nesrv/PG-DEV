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

s 1 'CREATE TABLE users_depts(
  login text,
  department text
);'
s 1 "INSERT INTO users_depts VALUES 
  ('alice',  'PR'),
  ('bob',    'Sales');"

s 1 'CREATE TABLE revenue(
  department text,
  amount numeric(10,2)
);'
s 1 "INSERT INTO revenue SELECT 'PR',   -random()* 100.00 FROM generate_series(1,100000);"
s 1 "INSERT INTO revenue SELECT 'Sales', random()*1000.00 FROM generate_series(1,10000);"

s 1 'CREATE POLICY departments ON revenue
  USING (department IN (SELECT department FROM users_depts WHERE login = current_user));'

s 1 'ALTER TABLE revenue ENABLE ROW LEVEL SECURITY;'

s 1 'GRANT SELECT ON users_depts TO alice, bob;'
s 1 'GRANT SELECT, INSERT ON revenue TO alice, bob;'

p

###############################################################################
h '2. Представление.'

s 1 "CREATE VIEW vrevenue AS (
	SELECT department, sum(amount) FROM revenue GROUP BY department
);"

s 1 'GRANT SELECT ON vrevenue  TO alice, bob;'

s 1 "SELECT * FROM vrevenue;"

p

###############################################################################
h '3. Проверка в сеансах пользователей.'

c 'Алиса:'
s 1 '\c - alice'
PSQL_PROMPT1='alice=> '
s 1 "SELECT * FROM vrevenue;"
c 'RLS на таблицу не сработала, так как запрос к представлению был выполнен от имени его владельца - student.'

c 'Боб:'
s 1 '\c - bob'
PSQL_PROMPT1='bob=> '
s 1 "SELECT * FROM vrevenue;"
c 'То же самое.'

p

###############################################################################
h '4. Свойство представления security_invoker.'

s 1 '\c - student'
PSQL_PROMPT1='student=# '

s 1 'ALTER VIEW vrevenue SET (security_invoker);'

c 'Алиса:'
s 1 '\c - alice'
PSQL_PROMPT1='alice=> '
s 1 "SELECT * FROM vrevenue;"
c 'Теперь RLS на таблицу сработала.'

c 'Боб:'
s 1 '\c - bob'
PSQL_PROMPT1='bob=> '
s 1 "SELECT * FROM vrevenue;"
c 'В сеансе Боба - тоже.'
p

stop_here

###############################################################################
psql_close 1
