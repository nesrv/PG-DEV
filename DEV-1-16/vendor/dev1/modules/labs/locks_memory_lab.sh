#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Закрепление буфера при открытом курсоре'

c 'Сначала выполняем подготовительные действия.'

c 'Устанавливаем необходимые расширения:'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_wait_sampling';"
pgctl_restart A

psql_open A 1
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
export PID1=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")

s 1 "CREATE EXTENSION pg_wait_sampling;"
s 1 "CREATE EXTENSION pg_buffercache;"

c 'Таблица, как в предыдущих практиках:'

s 1 'CREATE TABLE accounts(acc_no integer, amount numeric);'
s 1 "INSERT INTO accounts VALUES (1,1000.00),(2,2000.00),(3,3000.00);"

c 'Изменим остаток по счету 2 — в странице появится мертвая версия строки:'
s 1 "UPDATE accounts SET amount = 2500 WHERE acc_no = 2;"

p

c 'Начинаем транзакцию, открываем курсор и выбираем одну строку.'

s 1 "BEGIN;"
s 1 "DECLARE c CURSOR FOR SELECT * FROM accounts;"
s 1 "FETCH c;"

c 'Проверим, закреплен ли буфер:'

s 1 "SELECT * FROM pg_buffercache
WHERE relfilenode = pg_relation_filenode('accounts') AND relforknumber = 0 \gx"

c 'Да, pinning_backends = 1.'


###############################################################################
h '2. Очистка закрепленного буфера'

c 'Выполним очистку:'

psql_open A 2 $TOPIC_DB

s 2 "VACUUM VERBOSE accounts;"

c 'Как мы видим, мертвая строка не была очищена:  ...tuples missed: 1 dead from 1 pages not removed due to cleanup lock contention.'
c 'Если буфер закреплен, из страницы запрещено удалять версии строк. Но очистка не ждет, пока буфер освободится — строка будет очищена при следующем сеансе очистки.'

###############################################################################
h '3. Заморозка закрепленного буфера'

c 'Выполняем очистку с заморозкой:'

ss 2 "VACUUM FREEZE VERBOSE accounts;"

sleep 5

c 'Очистка зависает до закрытия курсора. При явно запрошенной заморозке нельзя оставить необработанной ни одну страницу, не отмеченную в карте заморозки — иначе невозможно уменьшить максимальный возраст незамороженных транзакций в pg_class.relfrozenxid.'

s 1 "SELECT age(relfrozenxid) FROM pg_class WHERE oid = 'accounts'::regclass;"
s 1 "COMMIT;"
r 2
s 1 "SELECT age(relfrozenxid) FROM pg_class WHERE oid = 'accounts'::regclass;"

c 'Профиль ожиданий:'

s 1 "SELECT p.pid, a.backend_type, a.application_name AS app, p.event_type, p.event, p.count
FROM pg_wait_sampling_profile p
  LEFT JOIN pg_stat_activity a ON p.pid = a.pid
WHERE event_type = 'BufferPin'
ORDER BY p.pid, p.count DESC;"

c 'Тип ожидания BufferPin говорит о том, что очистка ждала освобождения буфера.'

###############################################################################

stop_here
cleanup
