#!/bin/bash

. ../lib

init

psql_open A 2
psql_open A 3

start_here

###############################################################################
h '0. Подготовка'

c 'Создадим таблицу как в демонстрации; номер счета будет первичным ключом.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE accounts(acc_no integer PRIMARY KEY, amount numeric);'
s 1 "INSERT INTO accounts VALUES (1,1000.00),(2,2000.00),(3,3000.00);"

c 'Нам понадобятся два дополнительных сеанса.'

s 2 "\c $TOPIC_DB"
s 3 "\c $TOPIC_DB"

###############################################################################
h '1. Блокировки читающей транзакции, Read Committed'

c 'Начинаем транзакцию и читаем одну строку.'

export PID2=$(s_bare 2 "SELECT pg_backend_pid();")
s 2 'SELECT pg_backend_pid();'
s 2 "BEGIN;"
s 2 "SELECT * FROM accounts WHERE acc_no = 1;"

c 'Блокировки:'

s 1 "SELECT locktype, relation::regclass, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = $PID2;"

c 'Здесь мы видим:'
ul 'Блокировку таблицы accounts в режиме AccessShareLock;'
ul 'Блокировку индекса accounts_pkey, созданного для первичного ключа, в том же режиме;'
ul 'Исключительную блокировку собственного номера виртуальной транзакции.'

c 'Если смотреть блокировки в самой транзакции, к ним добавится блокировка на представление pg_locks:'

s 2 "SELECT locktype, relation::regclass, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = $PID2;"

s 2 "COMMIT;"

###############################################################################
h '2. Повышение уровня предикатных блокировок'

c 'В двух сеансах начинаем транзакции с уровнем Serializable.'

s 2 "BEGIN ISOLATION LEVEL SERIALIZABLE;"
s 3 "BEGIN ISOLATION LEVEL SERIALIZABLE;"

c 'В первой читаем строки счетов 1 и 3, во второй – строки счетов 2 и 3.'

s 2 "SELECT * FROM accounts WHERE acc_no IN (1,3);"
s 3 "SELECT * FROM accounts WHERE acc_no IN (2,3);"

c 'Блокируются страница индекса и отдельные версии строк:'

s 1 "SELECT pid, locktype, relation::regclass, page, tuple, mode, granted
FROM pg_locks
WHERE mode = 'SIReadLock'
ORDER BY 1,2,3,4,5;"

c 'Изменим в первом сеансе остаток первого счета, во втором – второго.'

s 2 "UPDATE accounts SET amount = amount + 10 WHERE acc_no = 1;"
s 3 "UPDATE accounts SET amount = amount + 10 WHERE acc_no = 2;"

c 'Транзакции сериализуются:'

s 2 "COMMIT;"
s 3 "COMMIT;"

c 'Теперь настроим повышение уровня так, чтобы при блокировке двух версий строк блокировалась вся таблица.'

s 1 "ALTER SYSTEM SET max_pred_locks_per_relation = 1;"

pgctl_reload A

c 'Повторяем опыт.'

s 2 "BEGIN ISOLATION LEVEL SERIALIZABLE;"
s 3 "BEGIN ISOLATION LEVEL SERIALIZABLE;"

s 2 "SELECT * FROM accounts WHERE acc_no IN (1,3);"
s 3 "SELECT * FROM accounts WHERE acc_no IN (2,3);"

c 'Теперь каждая транзакция блокирует всю таблицу:'

s 1 "SELECT pid, locktype, relation::regclass, page, tuple, mode, granted
FROM pg_locks
WHERE mode = 'SIReadLock'
ORDER BY 1,2,3,4,5;"

c 'Изменяем остатки...'

s 2 "UPDATE accounts SET amount = amount + 10 WHERE acc_no = 1;"
s 3 "UPDATE accounts SET amount = amount + 10 WHERE acc_no = 2;"

c '...и фиксируем транзакции.'

s 2 "COMMIT;"
s 3 "COMMIT;"

c 'Из-за повышения уровня блокировок сериализация невозможна.'

###############################################################################
h '3. Вывод в журнал информации о блокировках'

c 'Требуется изменить параметры:'

s 1 "ALTER SYSTEM SET log_lock_waits = on;"
s 1 "ALTER SYSTEM SET deadlock_timeout = '100ms';"
s 1 "SELECT pg_reload_conf();"

c 'Воспроизведем блокировку.'

s 1 'BEGIN;'
s 1 'UPDATE accounts SET amount = 10.00 WHERE acc_no = 1;'

s 2 'BEGIN;'
ss 2 'UPDATE accounts SET amount = 100.00 WHERE acc_no = 1;'

c 'В первом сеансе выполним задержку и после этого завершим транзакцию.'

s 1 "SELECT pg_sleep(1);"
s 1 "COMMIT;"
r 2
s 2 "COMMIT;"

c 'Вот что попало в журнал:'

e "tail -n 7 $LOG_A"

###############################################################################

stop_here
cleanup
