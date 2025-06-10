#!/bin/bash

. ../lib

init

psql_open A 2
psql_open A 3

start_here 19

###############################################################################

h 'Блокировки отношений и других объектов'

c 'Создадим таблицу «банковских» счетов. В ней будем хранить номер счета и сумму.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
export PID1=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")
s 1 'CREATE TABLE accounts(acc_no integer, amount numeric);'
s 1 "INSERT INTO accounts VALUES (1,1000.00), (2,2000.00), (3,3000.00);"

c 'Во втором сеансе начнем транзакцию. Нам понадобится номер обслуживающего процесса.'

s 2 "\c $TOPIC_DB"
export PID2=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")
s 2 'SELECT pg_backend_pid();'
s 2 'BEGIN;'

c 'Какие блокировки удерживает только что начавшаяся транзакция?'

s 1 "SELECT locktype, relation::regclass, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = $PID2;"

c 'Только блокировку собственного виртуального номера.'

p

c 'Теперь обновим строку таблицы. Как изменится ситуация?'

s 2 "UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;"

s 1 "SELECT locktype, relation::regclass, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = $PID2;"

c 'Добавилась блокировка отношения в режиме RowExclusiveLock (что соответствует команде UPDATE) и исключительная блокировка собственного номера (который появился, как только транзакция начала изменять данные).'

p

c 'Теперь попробуем в еще одном сеансе создать индекс по таблице.'

s 3 "\c $TOPIC_DB"
export PID3=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")
s 3 'SELECT pg_backend_pid();'
ss 3 "CREATE INDEX ON accounts(acc_no);"

c 'Команда не выполняется — ждет освобождения блокировки. Какой?'

s 1 "SELECT locktype, relation::regclass, virtualxid AS virtxid, transactionid AS xid, mode, granted,
   to_char(waitstart, 'HH24:MI:SS') AS waitstart FROM pg_locks WHERE pid = $PID3;"

c 'Видим, что транзакция пыталась получить блокировку таблицы в режиме ShareLock, но не смогла (granted = f).'\
' Столбец waitstart в этом случае показывает время, когда серверный процесс начал ожидать блокировку.'

p

c 'Мы можем найти номер блокирующего процесса (в общем виде — несколько номеров)...'

s 1 "SELECT pg_blocking_pids($PID3);"

c '...и посмотреть информацию о сеансах, к которым они относятся:'

s 1 "SELECT * FROM pg_stat_activity
WHERE pid = ANY(pg_blocking_pids($PID3)) \gx"

c 'После завершения транзакции блокировки снимаются и индекс создается.'

s 2 "COMMIT;"

r 3

###############################################################################
P 21
h 'Рекомендательные блокировки'

c 'Начнем транзакцию.'

s 2 "BEGIN;"

c 'Получим блокировку некого условного ресурса. В качестве идентификатора используется число; если ресурс имеет имя, удобно получить это число с помощью функции хеширования:'

s 2 "SELECT hashtext('ресурс1');"
s 2 "SELECT pg_advisory_lock(hashtext('ресурс1'));"

c 'Информация о рекомендательных блокировках доступна в pg_locks:'

s 1 "SELECT locktype, objid, virtualxid AS virtxid, mode, granted 
FROM pg_locks WHERE pid = $PID2;"

c 'Если другой сеанс попробует захватить ту же блокировку, он будет ждать ее освобождения:'

ss 3 "SELECT pg_advisory_lock(hashtext('ресурс1'));"

c 'В приведенном примере блокировка действует до конца сеанса, а не транзакции, как обычно.'

s 2 "COMMIT;"
s 1 "SELECT locktype, objid, virtualxid AS virtxid, mode, granted
FROM pg_locks WHERE pid = $PID2;"

c 'Захвативший блокировку сеанс может получить ее повторно, даже если есть очередь ожидания.'
s 2 "SELECT pg_advisory_lock(hashtext('ресурс1'));"

c 'Блокировку можно явно освободить:'

s 2 "SELECT pg_advisory_unlock(hashtext('ресурс1'));"

c 'Но в нашем примере блокировка была получена сеансом дважды, поэтому придется освободить ее еще раз:'

s 1 "SELECT locktype, objid, virtualxid AS virtxid, mode, granted
FROM pg_locks WHERE pid = $PID2;"

s 2 "SELECT pg_advisory_unlock(hashtext('ресурс1'));"

r 3

c 'Существуют другие варианты функций для получения рекомендательных блокировок до конца транзакции, для получения разделяемых блокировок и т. п. Вот их полный список:'

s 1 "\df pg_advisory*"

###############################################################################
P 25
h 'Предикатные блокировки'

c 'Начнем транзакцию с уровнем Serializable и прочитаем одну строку таблицы последовательным сканированием.'

s 2 "BEGIN ISOLATION LEVEL SERIALIZABLE;"
s 2 "EXPLAIN (analyze,costs off,timing off) SELECT * FROM accounts LIMIT 1;"

c 'Посмотрим на блокировки:'

s 1 "SELECT locktype, relation::regclass, page, tuple, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = $PID2;"

c 'Появилась предикатная блокировка всей таблицы accounts (несмотря на то что читается одна строка).'

s 2 "COMMIT;"

c 'Теперь прочитаем одну строку таблицы, используя индекс:'

s 2 "BEGIN ISOLATION LEVEL SERIALIZABLE;"
s 2 "SET enable_seqscan = off;"
s 2 "EXPLAIN (analyze,costs off,timing off) SELECT * FROM accounts WHERE acc_no = 1;"

c 'Блокировки:'

s 1 "SELECT locktype, relation::regclass, page, tuple, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = $PID2;"

c 'При индексном сканировании устанавливаются мелкогранулярные предикатные блокировки:'
ul 'блокировки прочитанных страниц индекса;'
ul 'блокировки прочитанных версий строк.'

s 2 "COMMIT;"

###############################################################################

stop_here
cleanup
demo_end
