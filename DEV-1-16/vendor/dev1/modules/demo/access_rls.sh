#!/bin/bash

. ../lib
init

start_here 5

###############################################################################
h 'Пример политики защиты строк'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Алиса и Боб работают в разных отделах одной компании.'

PSQL_PROMPT1='student=# '
s 1 'CREATE ROLE alice LOGIN;'
s 1 'CREATE ROLE bob LOGIN;'

s 1 'CREATE TABLE users_depts(
  login text,
  department text
);'
s 1 "INSERT INTO users_depts VALUES ('alice','PR'), ('bob','Sales');"

c 'Они обращаются к одной таблице, содержащей информацию обо всех отделах. При этом и Алиса, и Боб должны видеть данные только своего отдела.'

s 1 'CREATE TABLE revenue(
  department text,
  amount numeric(10,2)
);'
s 1 "INSERT INTO revenue SELECT 'PR',   -random()* 100.00 FROM generate_series(1,100000);"
s 1 "INSERT INTO revenue SELECT 'Sales', random()*1000.00 FROM generate_series(1,10000);"

c 'Определим соответствующую политику и включим ее:'

s 1 'CREATE POLICY departments ON revenue
  USING (department = (SELECT department FROM users_depts WHERE login = current_user));'
s 1 'ALTER TABLE revenue ENABLE ROW LEVEL SECURITY;'

c 'И нужно выдать Алисе и Бобу привилегии:'

s 1 'GRANT SELECT ON users_depts, revenue TO alice, bob;'

c 'Суперпользователь (он же владелец в данном случае) видит все строки независимо от политики:'

s 1 'SELECT department, sum(amount) FROM revenue GROUP BY department;'

c 'А что увидят Алиса и Боб?'

psql_open A 2 -d $TOPIC_DB -U alice
PSQL_PROMPT2='alice=> '

s 2 'SELECT department, sum(amount) FROM revenue GROUP BY department;'

psql_open A 3 -d $TOPIC_DB -U bob
PSQL_PROMPT3='bob=> '

s 3 'SELECT department, sum(amount) FROM revenue GROUP BY department;'

P 7

###############################################################################
h 'Несколько политик'

c 'Разрешим теперь Бобу добавлять строки в таблицу, но только для своего отдела и только в пределах 100 рублей:'
ul 'первое требование будет выполнено автоматически (единственный предикат работает и для существующих, и для новых строк);'
ul 'для второго создадим новую ограничительную политику.'

s 1 'CREATE POLICY amount ON revenue AS RESTRICTIVE
  USING (true)                        -- видны все существующие строки
  WITH CHECK (abs(amount) <= 100.00); -- новые строки должны удовлетворять'
s 1 'GRANT INSERT ON revenue TO bob;'

c 'Проверим:'

s 3 "INSERT INTO revenue VALUES ('Sales', 42.00);"
s 3 "INSERT INTO revenue VALUES ('PR', 42.00);"
s 3 "INSERT INTO revenue VALUES ('Sales', 1000.00);"

p

c 'Политики, созданные для таблицы, показывают команды psql \d (описание объекта) и \dp (описание привилегий), например:'

s 1 '\d revenue'

c 'Эту информацию можно получить и из представления pg_policies системного каталога.'

###############################################################################
stop_here

psql_close 3
psql_close 2

demo_end
