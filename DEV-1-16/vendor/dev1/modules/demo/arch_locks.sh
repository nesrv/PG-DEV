#!/bin/bash

. ../lib

init

psql_open A 2
psql_open A 3

start_here 6

###############################################################################
h 'Блокировка номера транзакции'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Начнем в другом сеансе новую транзакцию.'

s 2 "\c $TOPIC_DB"
s 2 'BEGIN;'

c 'Нам понадобится номер обслуживающего процесса:'

s 2 'SELECT pg_backend_pid();'

c 'Все «обычные» блокировки видны в представлении pg_locks. Какие блокировки удерживает только что начатая транзакция?'

s 1 "SELECT locktype, virtualxid AS virtxid, transactionid AS xid,
    mode, granted
FROM pg_locks
WHERE pid = $PID2;"

ul 'locktype — тип ресурса,'
ul 'mode — режим блокировки,'
ul 'granted — удалось ли получить блокировку.'

c 'Каждой транзакции сразу выдается виртуальный номер, и транзакция удерживает его исключительную блокировку.'

c 'Как только транзакция начинает менять какие-либо данные, ей выдается настоящий номер, который учитывается в правилах видимости. Номер можно получить и явно:'

s 2 "SELECT pg_current_xact_id();"

s 1 "SELECT locktype, virtualxid AS virtxid, transactionid AS xid,
    mode, granted
FROM pg_locks
WHERE pid = $PID2;"

c 'Теперь транзакция удерживает исключительную блокировку обоих номеров.'

P 10

###############################################################################
h 'Блокировка отношений'

c 'Создадим таблицу банковских счетов с тремя строками:'

s 1 'CREATE TABLE accounts(acc_no integer, amount numeric);'
s 1 "INSERT INTO accounts VALUES (1,100.00), (2,200.00), (3,300.00);"

c 'Вторая транзакция, которую мы не завершали, продолжает работу. Выполним в ней запрос к таблице:'

s 2 "SELECT * FROM accounts;"

c 'Как изменятся блокировки?'

s 1 "SELECT locktype, relation::regclass, virtualxid AS virtxid,
    transactionid AS xid, mode, granted
FROM pg_locks
WHERE pid = $PID2;"

c 'Добавилась блокировка таблицы в режиме Access Share. Она совместима с блокировкой любого режима, кроме Access Exclusive, поэтому не мешает практически никаким операциям, но не дает, например, удалить таблицу. Попробуем.'

s 3 "\c $TOPIC_DB"
s 3 'BEGIN;'
s 3 'SELECT pg_backend_pid();'
ss 3 'DROP TABLE accounts;'
sleep 1

c 'Команда не выполняется — ждет освобождения блокировки. Какой?'

s 1 "SELECT locktype, relation::regclass, virtualxid AS virtxid,
    transactionid AS xid, mode, granted 
FROM pg_locks
WHERE pid = $PID3;"

c 'Транзакция пыталась получить блокировку таблицы в режиме Access Exclusive, но не смогла (granted = f).'

p

c 'Информацию о том, что транзакция ожидает чего-то для продолжения работы, можно получить и так:'

s 1 "SELECT state, wait_event_type, wait_event
FROM pg_stat_activity
WHERE pid = $PID3;"

ul "state — состояние: активная транзакция, выполняющая команду;"
ul "wait_event_type — тип ожидания: блокировка (бывают и другие, например, ожидание ввода-вывода);"
ul "wait_event — конкретное ожидание: ожидание блокировки отношения."

p

c 'Мы можем найти номер блокирующего процесса (в общем случае — несколько номеров)...'

s 1 "SELECT pg_blocking_pids($PID3);"

c '...и посмотреть информацию о сеансах, к которым они относятся:'

s 1 "SELECT * FROM pg_stat_activity
WHERE pid = ANY(pg_blocking_pids($PID3)) \gx"

c 'После завершения транзакции все блокировки снимаются и таблица удаляется:'

s 2 "COMMIT;"

r 3

s 3 'COMMIT;'

P 14

###############################################################################
h 'Блокировка строк'

c 'Снова создадим таблицу счетов, но теперь сделаем номер счета первичным ключом:'

s 1 'CREATE TABLE accounts(acc_no integer PRIMARY KEY, amount numeric);'
s 1 "INSERT INTO accounts VALUES (1,100.00), (2,200.00), (3,300.00);"

c 'В новой транзакции обновим сумму первого счета (при этом ключ не меняется):'

s 2 'BEGIN;'
s 2 'UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;'
s 2 'SELECT pg_current_xact_id();'

c 'Как правило, признаком блокировки строки служит номер блокирующей транзакции, записанный в поле xmax (и еще ряд информационных битов, определяющих режим блокировки):'

s 1 "SELECT xmax, * FROM accounts;"

c 'Но в случае разделяемых блокировок такой способ не годится, поскольку в xmax нельзя записать несколько номеров транзакций. В таком случае номера транзакций хранятся в отдельной структуре, называемой мультитранзакцией, а в xmax помещается ссылка на нее. Но мы не будем вдаваться в детали реализации блокировок строк, а просто воспользуемся расширением pgrowlocks:'

s 1 "CREATE EXTENSION pgrowlocks;"
s 1 "SELECT locked_row, xids, modes, pids FROM pgrowlocks('accounts');"

c 'Чтобы показать блокировки, расширение читает табличные страницы (в отличие от обращения к pg_locks, которое читает данные из оперативной памяти).'

c 'Теперь изменим номер второго счета (при этом меняется ключ):'
s 2 'UPDATE accounts SET acc_no = 20 WHERE acc_no = 2;'
s 1 "SELECT locked_row, xids, modes, pids FROM pgrowlocks('accounts');"

c 'Чтобы продемонстрировать разделяемые блокировки, начнем еще одну транзакцию. Все запрашиваемые блокировки будут совместимы друг с другом.'


s 3 'BEGIN;'
s 3 'SELECT * FROM accounts WHERE acc_no = 1 FOR KEY SHARE;'
s 3 'SELECT * FROM accounts WHERE acc_no = 3 FOR SHARE;'
s 3 'SELECT pg_current_xact_id();'

s 1 "SELECT locked_row, xids, modes, pids FROM pgrowlocks('accounts');"

s 2 "ROLLBACK;"
s 3 "ROLLBACK;"

p

###############################################################################
h 'Как не ждать блокировку?'

c 'Иногда удобно не ждать освобождения блокировки, а сразу получить ошибку, если необходимый ресурс занят. Приложение может перехватить и обработать такую ошибку.'

c 'Для этого ряд команд SQL (такие, как SELECT и некоторые варианты ALTER) позволяют указать ключевое слово NOWAIT. Заблокируем таблицу, обновив первую строку:'

s 1 "BEGIN;"
s 1 "UPDATE accounts SET amount = amount + 1 WHERE acc_no = 1;"

s 2 "BEGIN;"
s 2 "LOCK TABLE accounts NOWAIT; -- IN ACCESS EXCLUSIVE MODE"

c 'Транзакция сразу же получает ошибку.'

s 2 "ROLLBACK;"

p

c 'Команды UPDATE и DELETE не позволяют указать NOWAIT. Но можно сначала выполнить команду'

s_fake 1 "SELECT ... FOR UPDATE NOWAIT; -- или FOR NO KEY UPDATE NOWAIT"

c 'а затем, если строки успешно заблокированы, изменить или удалить их. Например:'

s 2 "BEGIN;"
s 2 "SELECT * FROM accounts WHERE acc_no = 1 FOR UPDATE NOWAIT;"

c 'Снова тут же получаем ошибку - строка уже заблокирована. Но при успехе SELECT ... FOR UPDATE в этой транзакции можно было бы далее изменять заблокированную строку.'

s 2 "ROLLBACK;"

c 'Другой подход к блокировке строк предоставляет предложение SKIP LOCKED. Запросим блокировку одной строки, не указывая конкретный номер счета:'

s 2 "BEGIN;"
s 2 "SELECT * FROM accounts ORDER BY acc_no
FOR UPDATE SKIP LOCKED LIMIT 1;"

c 'В этом случае команда пропускает уже заблокированную первую строку и мы немедленно получаем блокировку второй строки. Этот прием уже использовался в практике темы «Очистка» при выборе пакета строк для обновления. Еще одно применение — в организации очередей — будет рассмотрено в теме «Асинхронная обработка».'

s 2 "ROLLBACK;"

p

c 'Для команд, не связанных с блокировкой строк, использовать NOWAIT не получится. В этом случае можно установить небольшой таймаут ожидания (по умолчанию он не задан и ожидание будет бесконечным):'

s 2 "SET lock_timeout = '1s';"
s 2 "ALTER TABLE accounts DROP COLUMN amount;"

c 'Получаем ошибку без длительного ожидания освобождения ресурса.'

s 2 "RESET lock_timeout;"

s 1 "ROLLBACK;"

P 21

###############################################################################
h '«Очередь» ожидания'

c 'Начинаем транзакцию и обновляем строку.'

s 1 "BEGIN;"
s 1 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;"

c 'Будем смотреть только на блокировки, связанные с номерами транзакций и версиями строк:'

s 1 "SELECT pid, locktype, page, tuple, transactionid AS xid,
    mode, granted
FROM pg_locks WHERE locktype IN ('transactionid','tuple')
ORDER BY pid, granted DESC, locktype;"

c 'Другая транзакция пытается обновить ту же строку:'

s 2 "BEGIN;"
ss 2 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;"
sleep 1

c 'Какие при этом возникают блокировки?'

s 1 "SELECT pid, locktype, page, tuple, transactionid AS xid,
    mode, granted
FROM pg_locks WHERE locktype IN ('transactionid','tuple')
ORDER BY pid, granted DESC, locktype;"

c 'Транзакция захватила блокировку, связанную с версией строки 1 на странице 0, и ждет завершения первой транзакции:'

s 1 "SELECT pid, pg_blocking_pids(pid) FROM pg_stat_activity
WHERE pid IN ($PID1,$PID2) ORDER BY pid;"

c 'Теперь следующая транзакция пытается обновить ту же строку:'

s 3 "BEGIN;"
ss 3 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;"
sleep 1

c 'Что увидим в pg_locks на этот раз?'

s 1 "SELECT pid, locktype, page, tuple, transactionid AS xid,
    mode, granted
FROM pg_locks WHERE locktype IN ('transactionid','tuple')
ORDER BY pid, granted DESC, locktype;"

c 'Транзакция встала в очередь за блокировкой версии строки, очередь выросла:'

s 1 "SELECT pid, pg_blocking_pids(pid) FROM pg_stat_activity 
WHERE pid IN ($PID1,$PID2,$PID3) ORDER BY pid;"

c 'Если теперь первая транзакция успешно завершается...'

s 1 "COMMIT;"
r 2

c '...выполняется UPDATE и первая версия становится неактуальной.'

s 1 "SELECT pid, locktype, page, tuple, transactionid AS xid,
    mode, granted
FROM pg_locks WHERE locktype IN ('transactionid','tuple')
ORDER BY pid, granted DESC, locktype;"

c 'Все транзакции, которые стояли в очереди, будут теперь ожидать завершения второй транзакции — и будут обрабатываться в произвольном порядке. Вот как выглядит очередь в нашем случае:'

s 1 "SELECT pid, pg_blocking_pids(pid) FROM pg_stat_activity 
WHERE pid IN ($PID2,$PID3) ORDER BY pid;"

s 2 "COMMIT;"
r 3
s 3 "COMMIT;"

###############################################################################

stop_here
cleanup
demo_end
