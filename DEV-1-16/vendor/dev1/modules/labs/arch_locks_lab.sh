#!/bin/bash

. ../lib

init

psql_open A 2

start_here

###############################################################################
h '1. Блокировки при чтении строки по первичному ключу'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'SELECT pg_backend_pid();'
export PID1=`sudo -i -u $OSUSER psql -A -t -X -d postgres -c "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1"`

c 'Создадим таблицу как в демонстрации:'

s 1 'CREATE TABLE accounts(acc_no integer PRIMARY KEY, amount numeric);'
s 1 "INSERT INTO accounts VALUES (1,100.00), (2,200.00), (3,300.00);"

c 'Прочитаем строку, начав транзакцию:'

s 2 "\c $TOPIC_DB"
s 2 'SELECT pg_backend_pid();'
export PID2=`sudo -i -u $OSUSER psql -A -t -X -d postgres -c "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1"`

s 2 "BEGIN;"
s 2 "SELECT * FROM accounts WHERE acc_no = 1;"

c 'Блокировки включают блокировку индекса, поддерживающего ограничение первичного ключа, в режиме Access Share:'

s 1 "SELECT locktype, relation::REGCLASS, virtualxid AS virtxid,
    transactionid AS xid, mode, granted
FROM pg_locks
WHERE pid = $PID2;"

s 2 "COMMIT;"

###############################################################################
h '2. Рекомендательные блокировки'

c 'Захватим рекомендательную блокировку уровня сеанса:'

s 2 "BEGIN;"
s 2 "SELECT pg_advisory_lock(42);"

c 'Блокировка:'

s 1 "SELECT locktype, virtualxid AS virtxid, objid, mode, granted
FROM pg_locks
WHERE pid = $PID2;"

c 'Идентификатор ресурса для блокировки типа advisory отображается в столбце objid.'

s 2 "COMMIT;"

###############################################################################
h '3. Проверка внешнего ключа'

c 'Нам понадобится расширение для анализа блокировок на уровне строк:'

s 1 "CREATE EXTENSION pgrowlocks;"

c 'Создадим таблицу клиентов:'

s 1 "CREATE TABLE clients(
    client_id integer PRIMARY KEY,
    name text
);"
s 1 "INSERT INTO clients VALUES (10,'alice'), (20,'bob');"

c 'В таблицу счетов добавим столбец для идентификатора клиента и внешний ключ:'

s 1 "ALTER TABLE accounts
    ADD client_id integer REFERENCES clients(client_id);"

c 'Внутри транзакции выполним какое-нибудь действие с таблицей счетов, вызывающее проверку внешнего ключа. Например, вставим строку:'

s 2 "BEGIN;"
s 2 "INSERT INTO accounts(acc_no, amount, client_id)
    VALUES (4,400.00,20);"

c 'Проверка внешнего ключа приводит к появлению блокировки строки в таблице клиентов в режиме KeyShare:'

s 1 "SELECT * FROM pgrowlocks('clients') \gx"

c 'Это не мешает изменять неключевые столбцы этой строки:'

s 1 "UPDATE clients SET name = 'brian' WHERE client_id = 20;"

s 2 "COMMIT;"

###############################################################################
h '4. Взаимоблокировка двух транзакций'

c 'Обычная причина возникновения взаимоблокировок — разный порядок блокирования строк таблиц в приложении.'
c 'Первая транзакция намерена перенести 100 рублей с первого счета на второй. Для этого она сначала уменьшает первый счет:'

s 1 "BEGIN;"
s 1 "UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;"

c 'В это же время вторая транзакция намерена перенести 10 рублей со второго счета на первый. Она начинает с того, что уменьшает второй счет:'

s 2 "BEGIN;"
s 2 "UPDATE accounts SET amount = amount - 10.00 WHERE acc_no = 2;"

c 'Теперь первая транзакция пытается увеличить второй счет...'

ss 1 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 2;"
sleep 1

c '...но обнаруживает, что строка заблокирована.'

c 'Затем вторая транзакция пытается увеличить первый счет...'

ss 2 "UPDATE accounts SET amount = amount + 10.00 WHERE acc_no = 1;"
sleep 1

c '...но тоже блокируется.'
c 'Возникает циклическое ожидание, которое никогда не завершится само по себе. Поэтому если какая-либо блокировка не получена за время, указанное в параметре deadlock_timeout (по умолчанию — 1 секунда), сервер проверяет наличие циклов ожидания. Обнаружив такой цикл, он прерывает одну из транзакций, чтобы остальные могли продолжить работу.'

r 2
r 1
s 1 "COMMIT;"
s 2 "COMMIT;"

c 'Взаимоблокировки обычно означают, что приложение спроектировано неправильно. Правильный способ выполнения таких операций — блокирование ресурсов в одном и том же порядке. Например, в данном случае можно блокировать счета в порядке возрастания их номеров.'

c 'Тем не менее взаимоблокировки могут возникать и при нормальной работе (например, могут взаимозаблокироваться две команды UPDATE одной и той же таблицы). Но это очень редкие ситуации.'

###############################################################################

stop_here
cleanup
