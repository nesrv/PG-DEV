#!/bin/bash

. ../lib

init

sudo service pgbouncer restart  # сбросить соединения

start_here

###############################################################################
h '1. Консоль pgbouncer'

c 'Дважды подключаемся к базе student ролью student:'

psql_open A 2 "postgresql://student@localhost:6432/student?password=student"
psql_open A 3 "postgresql://student@localhost:6432/student?password=student"

c 'Подключаемся к консоли pgbouncer:'

psql_open A 1 "postgresql://student@localhost:6432/pgbouncer?password=student"

s 1 '\x'
s 1 "SHOW CLIENTS;"

c 'Здесь отображаются три соединения к клиентами pgbouncer: два сеанса для student, подключенных к базе student, и одно подключение к консоли.'

s 1 "SHOW SERVERS;"

c 'Здесь видно, что сейчас используется только одно соединение pgbouncer с сервером баз данных.'

psql_close 1
psql_close 2
psql_close 3

###############################################################################
h '2. Функции nextval и currval'

c 'Все, что нужно сделать — заключить обе команды в одну транзакцию.'

c 'Но на практике не стоит напрямую вызывать функции управления последовательностями без особой необходимости. Лучше объявить автоматическую генерацию уникальных значений, как это определено стандартом SQL:'

psql_open A 1

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE TABLE master(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    s text
);"
s 1 "CREATE TABLE detail(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    m_id integer REFERENCES master(id),
    s text
);"

c 'А вставку можно организовать с помощью PL/pgSQL следующим образом:'

s 1 "DO \$\$
DECLARE
   m_id integer;
BEGIN
   INSERT INTO master(s) VALUES ('m1') RETURNING id INTO m_id;
   INSERT INTO detail(m_id, s) VALUES (m_id, 'd1');
END;
\$\$;"

psql_close 1

###############################################################################
h '3. Рекомендательные блокировки на уровне сеанса'

c 'Первый клиент устанавливает рекомендательную блокировку на уровне сеанса:'

psql_open A 1 "postgresql://student@localhost:6432/$TOPIC_DB?password=student"
s 1 "BEGIN;"
s 1 "SELECT pg_backend_pid();"
s 1 "SELECT pg_advisory_lock(42);"
s 1 "END;"

c 'Блокировка удерживается после окончания транзакции:'

s 1 "SELECT objid FROM pg_locks WHERE locktype = 'advisory';"

c 'Теперь появляется транзакция второго клиента:'

psql_open A 2 "postgresql://student@localhost:6432/$TOPIC_DB?password=student"

s 2 "BEGIN;"

c 'В это время первый клиент пытается освободить блокировку, но не может, поскольку выполняется в другом сеансе:'

s 1 "SELECT pg_advisory_unlock(42);"
s 1 "SELECT pg_backend_pid();"

c 'Зато может второй клиент, хоть он и не устанавливал эту блокировку:'

s 2 "SELECT pg_advisory_unlock(42);"
s 2 "COMMIT;"

###############################################################################

stop_here
cleanup
