#!/bin/bash

. ../lib

init

psql_open A 2
psql_open A 3

start_here

###############################################################################

h '1. Блокировки при нескольких обновлениях строки'

c 'Для простоты создадим таблицу без первичного ключа.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE accounts(acc_no integer, amount numeric);'
s 1 "INSERT INTO accounts VALUES (1,1000.00),(2,2000.00),(3,3000.00);"

c 'Создадим представление над pg_locks как в демонстрации:'

s 1 "CREATE VIEW locks AS
SELECT pid,
       locktype,
       CASE locktype
         WHEN 'relation' THEN relation::REGCLASS::text
         WHEN 'virtualxid' THEN virtualxid::text
         WHEN 'transactionid' THEN transactionid::text
         WHEN 'tuple' THEN relation::REGCLASS::text||':'||page::text||','||tuple::text
       END AS lockid,
       mode,
       granted
FROM pg_locks;"

c 'Первая транзакция обновляет и, соответственно, блокирует строку:'

s 1 "BEGIN;"
s 1 "SELECT pg_current_xact_id(), pg_backend_pid();"
s 1 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;"

c 'Вторая транзакция делает то же самое:'

s 2 "\c $TOPIC_DB"
s 2 "BEGIN;"
s 2 "SELECT pg_current_xact_id(), pg_backend_pid();"
ss 2 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;"

c 'И третья:'

s 3 "\c $TOPIC_DB"
s 3 "BEGIN;"
s 3 "SELECT pg_current_xact_id(), pg_backend_pid();"
ss 3 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;"

c 'Блокировки для первой транзакции:'

s 1 "SELECT * FROM locks WHERE pid = $PID1;"

ul 'Тип relation для pg_locks и locks в режиме AccessShareLock — устанавливаются на читаемые отношения.'
ul 'Тип relation для accounts в режиме RowExclusiveLock — устанавливается на изменяемое отношение.'
ul 'Типы virtualxid и transactionid в режиме ExclusiveLock — удерживаются транзакцией для самой себя.'

c 'Блокировки для второй транзакции:'

s 1 "SELECT * FROM locks WHERE pid = $PID2;"

c 'По сравнению с первой транзакцией:'
ul 'Блокировки для pg_locks и locks отсутствуют, так как вторая транзакция не обращалась к этим отношениям.'
ul 'Транзакция ожидает получение блокировки типа transactionid в режиме ShareLock для первой транзакции. '
ul 'Удерживается блокировка типа tuple для обновляемой строки.'

c 'Блокировки для третьей транзакции:'

s 1 "SELECT * FROM locks WHERE pid = $PID3;"

ul 'Транзакция ожидает получение блокировки типа tuple для обновляемой строки.'

c 'Общую картину текущих ожиданий можно увидеть в представлении pg_stat_activity. Для удобства можно добавить и информацию о блокирующих процессах:'

s 1 "SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid) 
FROM pg_stat_activity 
WHERE backend_type = 'client backend';"

s 1 "ROLLBACK;"
r 2
s 2 "ROLLBACK;"
r 3
s 3 "ROLLBACK;"

###############################################################################
h '2. Взаимоблокировка трех транзакций'

c 'Воспроизведем взаимоблокировку трех транзакций.'

s 1 "BEGIN;"
s 1 "UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;"

s 2 "BEGIN;"
s 2 "UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 2;"

s 3 "BEGIN;"
s 3 "UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 3;"

ss 1 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 2;"
ss 2 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 3;"
ss 3 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;"

sleep 2

# Определяем, в каком терминале транзакция прервана
t0=$(psql -Atc "SELECT array_position(ARRAY[$PID1,$PID2,$PID3], (SELECT pid FROM pg_stat_activity WHERE datname='$TOPIC_DB' and state='idle in transaction (aborted)'));")

# Читаем его вывод
r $t0

# В двух других терминалах по цепочке ожиданий (1-3-2-1) читаем вывод и завершаем транзакцию
t=$t0
for i in {1,2}; do
	t=$((($t+4)%3+1)) # следующий терминал
	r $t
	s $t "COMMIT;"
done

# Завершаем прерванную транзакцию
s $t0 "COMMIT;"

c 'Вот какую информацию о взаимоблокировке можно получить из журнала:'
e "tail -n 10 $LOG_A"

###############################################################################
h '3. Взаимоблокировка двух операций UPDATE'

c 'Команда UPDATE блокирует строки по мере их обновления. Это происходит не одномоментно.'
c 'Поэтому если одна команда будет обновлять строки в одном порядке, а другая — в другом, они могут взаимозаблокироваться. Это может произойти, если для команд будут построены разные планы выполнения, например, одна будет читать таблицу последовательно, а другая — по индексу.'
c 'Получить такую ситуацию непросто даже специально, в реальной работе она маловероятна. Проиллюстрировать ее проще всего с помощью курсоров, поскольку это дает возможность управлять порядком чтения.'

s 2 "BEGIN;"
s 2 "DECLARE c1 CURSOR FOR
SELECT * FROM accounts ORDER BY acc_no
FOR UPDATE;"

s 3 "BEGIN;"
s 3 "DECLARE c2 CURSOR FOR
SELECT * FROM accounts ORDER BY acc_no DESC -- в обратную сторону
FOR UPDATE;"

s 2 "FETCH c1;"
s 3 "FETCH c2;"

s 2 "FETCH c1;"
ss 3 "FETCH c2;"
c 'Вторая команда ожидает блокировку...'

ss 2 "FETCH c1;"
c 'Произошла взаимоблокировка. И через некоторое время:'

sleep 2

r 3
r 2
s 2 "COMMIT;"
s 3 "COMMIT;"

###############################################################################

stop_here
cleanup
