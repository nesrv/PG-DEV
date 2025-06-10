#!/bin/bash

. ../lib

init

psql_open A 2
psql_open A 3
psql_open A 4

start_here 10

###############################################################################

h 'Блокировки строк'

c 'Наиболее частый случай блокировок — блокировки, возникающие на уровне строк.'

c 'Создадим таблицу счетов, как в прошлой теме.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
export PID1=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")
s 1 'CREATE TABLE accounts(acc_no integer PRIMARY KEY, amount numeric);'
s 1 "INSERT INTO accounts VALUES (1,1000.00),(2,2000.00),(3,3000.00);"

c 'Поскольку информация о блокировке строк хранится только в самих версиях строк, воспользуемся знакомым расширением pageinspect.'

s 1 'CREATE EXTENSION pageinspect;'

c 'Для удобства создадим представление, расшифровывающее интересующие нас информационные биты в первых трех версиях строк.'

s 1 "CREATE VIEW accounts_v AS
SELECT '(0,'||lp||')' AS ctid,
       t_xmax as xmax,
       CASE WHEN (t_infomask & 1024) > 0  THEN 't' END AS committed,
       CASE WHEN (t_infomask & 2048) > 0  THEN 't' END AS aborted,
       CASE WHEN (t_infomask & 128) > 0   THEN 't' END AS lock_only,
       CASE WHEN (t_infomask & 4096) > 0  THEN 't' END AS is_multi,
       CASE WHEN (t_infomask2 & 8192) > 0 THEN 't' END AS keys_upd
FROM heap_page_items(get_raw_page('accounts',0))
WHERE lp <= 3
ORDER BY lp;"

c 'Обновляем сумму первого счета (ключ не меняется) и номер второго счета (ключ меняется):'

s 2 "\c $TOPIC_DB"
export PID2=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")
s 2 'BEGIN;'
s 2 'UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;'
s 2 'UPDATE accounts SET acc_no = 20 WHERE acc_no = 2;'

c 'Заглянем в представление. Напомним, что оно показывает только первые три (то есть исходные) версии строк.'

s 1 'SELECT * FROM accounts_v;'

c 'По столбцу keys_upd видно, что строки, соответствующие первому и второму счету, заблокированы в разных режимах.'

p

c 'Теперь в другом сеансе запросим разделяемые блокировки первого и третьего счетов:'

s 3 "\c $TOPIC_DB"
export PID3=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")
s 3 'BEGIN;'
s 3 'SELECT * FROM accounts WHERE acc_no = 1 FOR KEY SHARE;'
s 3 'SELECT * FROM accounts WHERE acc_no = 3 FOR SHARE;'

c 'Все запрошенные блокировки совместимы друг с другом. В версиях строк видим:'

s 1 'SELECT * FROM accounts_v;'

c 'Столбец lock_only позволяет отличить просто блокировку от обновления или удаления. Видим также, что в первой строке обычный номер в столбце xmax заменен на номер мультитранзакции — об этом говорит столбец is_multi.'

p

c 'Чтобы не вникать в детали информационных битов и реализацию мультитранзакций, можно воспользоваться еще одним расширением, которое позволяет увидеть всю информацию о блокировках строк в удобном виде.'

s 1 "CREATE EXTENSION pgrowlocks;"

s 1 "SELECT * FROM pgrowlocks('accounts') \gx"

c 'Расширение дает информацию о номерах транзакций, мультитранзакций и режимах всех блокировок.'

s 2 'ROLLBACK;'
s 3 'ROLLBACK;'

###############################################################################
P 14
h '«Очередь» ожидания'

c 'Для удобства создадим представление над pg_locks, «свернув» в одно поле идентификаторы разных типов блокировок:'

s 1 "CREATE VIEW locks AS
SELECT pid,
       locktype,
       CASE locktype
         WHEN 'relation' THEN relation::regclass::text
         WHEN 'virtualxid' THEN virtualxid::text
         WHEN 'transactionid' THEN transactionid::text
         WHEN 'tuple' THEN relation::regclass::text||':'||page::text||','||tuple::text
       END AS lockid,
       mode,
       granted
FROM pg_locks;"

c 'Пусть одна транзакция заблокирует строку в разделяемом режиме...'

export PSQL_PROMPT1='S1=> '
s 1 "BEGIN;"
s 1 "SELECT pg_current_xact_id(), pg_backend_pid();"
s 1 "SELECT * FROM accounts WHERE acc_no = 1 FOR SHARE;"
export PSQL_PROMPT1='=> '

c '...а другая попробует выполнить обновление:'

export PSQL_PROMPT2='U1=> '
s 2 "BEGIN;"
s 2 "SELECT pg_current_xact_id(), pg_backend_pid();"
ss 2 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;"

c 'В представлении pg_locks можно увидеть, что вторая транзакция ожидает завершения первой (granted = f), удерживая при этом блокировку версии строки (locktype = tuple):'

s 1 "SELECT * FROM locks WHERE pid = $PID2; -- U1"

c 'Чтобы не разбираться, кто кого блокирует, по представлению pg_locks, можно узнать номер (или номера) процесса блокирующего сеанса с помощью функции:'

s 1 "SELECT pg_blocking_pids($PID2); -- U1"

c 'Теперь появляется транзакция, желающая получить несовместимую блокировку.'

export PSQL_PROMPT3='U2=> '
s 3 "BEGIN;"
s 3 "SELECT pg_current_xact_id(), pg_backend_pid();"
ss 3 "UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;"

c 'Она встает в очередь за транзакцией, удерживающей блокировку версии строки (locktype = tuple, granted = f):'

s 1 "SELECT * FROM locks WHERE pid = $PID3; -- U2"
s 1 "SELECT pg_blocking_pids($PID3); -- U2"

###############################################################################
P 18

c 'Транзакция, желающая заблокировать строку в разделяемом режиме, проходит в нашем примере без очереди.'

export PSQL_PROMPT4='S2=> '
s 4 "\c $TOPIC_DB"
export PID4=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")
s 4 "BEGIN;"
s 4 "SELECT pg_current_xact_id(), pg_backend_pid();"
s 4 "SELECT * FROM accounts WHERE acc_no = 1 FOR SHARE;"

c 'В версии строки теперь мультитранзакция:'

s 1 "SELECT * FROM pgrowlocks('accounts') \gx"

c 'После того как одна из транзакций, удерживающих строку в разделяемом режиме, завершится, другая продолжит удерживать блокировку.'

export PSQL_PROMPT1='S1=> '
s 1 "COMMIT;"
export PSQL_PROMPT1='=> '

c 'Транзакция, стоящая первой в очереди, теперь ждет завершения оставшейся транзакции.'

s 1 "SELECT * FROM locks WHERE pid = $PID2; -- U1"

c 'Обратите снимание, что в поле xmax остался номер мультитранзакции, хотя одна из входящих в нее транзакций уже завершилась. Этот номер может быть заменен на другой (новой мультитранзакции или обычной транзакции) при очистке.'

s 1 "SELECT * FROM pgrowlocks('accounts') \gx"

c 'Теперь завершается и вторая транзакция, удерживавшая разделяемую блокировку.'

s 4 "COMMIT;"

c 'Транзакция, стоявшая первой в очереди, получает доступ к версии строки:'

r 2
s 1 "SELECT * FROM pgrowlocks('accounts') \gx"

c 'Оставшаяся транзакция захватывает блокировку tuple версии строки и становится первой в очереди:'

s 1 "SELECT * FROM locks WHERE pid = $PID3; -- U2"

c 'Отменим изменения.'

s 2 "ROLLBACK;"
r 3
s 3 "ROLLBACK;"

export PSQL_PROMPT1='=> '
export PSQL_PROMPT2='=> '
export PSQL_PROMPT3='=> '
export PSQL_PROMPT4='=> '

###############################################################################
p
h 'Как не ждать блокировку?'

c 'Иногда удобно не ждать освобождения блокировки, а сразу получить ошибку, если необходимый ресурс занят. Приложение может перехватить и обработать такую ошибку.'

c 'Для этого ряд команд SQL (такие, как SELECT и некоторые варианты ALTER) позволяют указать ключевое слово NOWAIT. Заблокируем таблицу, обновив первую строку:'

s 1 "BEGIN;"
s 1 "UPDATE accounts SET amount = amount + 1 WHERE acc_no = 1;"

s 2 "BEGIN;"
s 2 "LOCK TABLE accounts NOWAIT; -- IN ACCESS EXCLUSIVE MODE"

c 'Транзакция сразу же получает ошибку.'

s 2 "ROLLBACK;"

c 'А для рекомендательных блокировок есть функции, позволяющие либо сразу захватить блокировку, либо вернуть false в случае неудачи:'

s 1 "\df pg_try_advisory*"

p

c 'Команды UPDATE и DELETE не позволяют указать NOWAIT. Но можно сначала выполнить команду'

s_fake 1 "SELECT ... FOR UPDATE NOWAIT; -- или FOR NO KEY UPDATE NOWAIT"

c 'а затем, если строки успешно заблокированы, изменить или удалить их. Например:'

s 2 "BEGIN;"
s 2 "SELECT * FROM accounts WHERE acc_no = 1 FOR UPDATE NOWAIT;"

c 'Тут же получаем ошибку и не пытаемся вызывать DELETE или UPDATE.'

s 2 "ROLLBACK;"

c 'Другой способ не ждать снятия блокировки строк предоставляет предложение SKIP LOCKED. Заблокируем одну строку, но без указания конкретного номера счета:'

s 2 "BEGIN;"
s 2 "SELECT * FROM accounts ORDER BY acc_no
FOR UPDATE SKIP LOCKED LIMIT 1;"

c 'В этом случае команда пропускает заблокированную первую строку и мы немедленно получаем блокировку уже второй строки.'

s 2 "ROLLBACK;"

p

c 'Для команд, не связанных с блокировкой строк, использовать NOWAIT не получится. В этом случае можно установить небольшой тайм-аут ожидания. (По умолчанию его значение нулевое, что означает бесконечное ожидание):'

s 2 "SET lock_timeout = '1s';"
s 2 "ALTER TABLE accounts DROP COLUMN amount;"

c 'Получаем ошибку без длительного ожидания освобождения ресурса.'

s 2 "RESET lock_timeout;"

c 'А при выполнении очистки можно указать, что она должна пропускать обработку таблицы, если ее блокировку не удалось получить немедленно. Это может оказаться особенно актуальным, когда выполняется очистка всей базы:'

s 2 "VACUUM (skip_locked);"

s 1 "ROLLBACK;"

###############################################################################
P 20
h 'Взаимоблокировка'

c 'Обычная причина возникновения взаимоблокировок — разный порядок блокирования строк таблиц.'
c 'Первая транзакция намерена перенести 100 рублей с первого счета на второй. Для этого она сначала уменьшает первый счет:'

s 2 "BEGIN;"
s 2 "UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;"

c 'В это же время вторая транзакция намерена перенести 10 рублей со второго счета на первый. Она начинает с того, что уменьшает второй счет:'

s 3 "BEGIN;"
s 3 "UPDATE accounts SET amount = amount - 10.00 WHERE acc_no = 2;"

c 'Теперь первая транзакция пытается увеличить второй счет, но обнаруживает, что строка заблокирована.'

ss 2 "UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 2;"

c 'Затем вторая транзакция пытается увеличить первый счет, но тоже блокируется.'

ss 3 "UPDATE accounts SET amount = amount + 10.00 WHERE acc_no = 1;"

c 'Возникает циклическое ожидание, которое никогда не завершится само по себе. Поэтому сервер, обнаружив такой цикл, прерывает одну из транзакций.'

r 2
r 3
s 2 "COMMIT;"
s 3 "COMMIT;"

c 'Правильный способ выполнения таких операций — блокирование ресурсов в одном и том же порядке. Например, в данном случае можно блокировать счета в порядке возрастания их номеров.'

###############################################################################

stop_here
cleanup
demo_end
