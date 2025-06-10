#!/bin/bash

. ../lib

init

start_here 7

###############################################################################
h 'Накопительная статистика'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Вначале включим сбор статистики ввода-вывода:'

s 1 "ALTER SYSTEM SET track_io_timing=on;"
s 1 "SELECT pg_reload_conf();"

c 'Смотреть на активности сервера имеет смысл, когда какие-то активности на самом деле есть. Чтобы сымитировать нагрузку, воспользуемся pgbench — штатной утилитой для запуска эталонных тестов.'
c 'Сначала утилита создает набор таблиц и заполняет их данными.'

e "pgbench -i $TOPIC_DB"

p

c 'Сбросим накопленную ранее статистику по базе данных:'
s 1 'SELECT pg_stat_reset();';

c 'А также статистику экземпляра по вводу-выводу:'
s 1 "SELECT pg_stat_reset_shared('io');";

c 'Запускаем тест TPC-B на несколько секунд:'

e "pgbench -T 10 $TOPIC_DB"

c 'Теперь мы можем посмотреть статистику обращений к таблицам в терминах строк:'

s 1 "SELECT *
FROM pg_stat_all_tables
WHERE relid = 'pgbench_accounts'::regclass \gx"

p

c 'И в терминах страниц:'

s 1 "SELECT *
FROM pg_statio_all_tables
WHERE relid = 'pgbench_accounts'::regclass \gx"

p

c 'Существуют аналогичные представления для индексов:'

s 1 "SELECT *
FROM pg_stat_all_indexes
WHERE relid = 'pgbench_accounts'::regclass \gx"

p

s 1 "SELECT *
FROM pg_statio_all_indexes
WHERE relid = 'pgbench_accounts'::regclass \gx"

p

c 'Эти представления, в частности, могут помочь определить неиспользуемые индексы. Такие индексы не только бессмысленно занимают место на диске, но и тратят ресурсы на обновление при каждом изменении данных в таблице.'

c 'Есть также представления для пользовательских и системных объектов (all, user, sys), для статистики текущей транзакции (pg_stat_xact*) и другие.'

p

c 'Можно посмотреть общую статистику по базе данных:'

s 1 "SELECT *
FROM pg_stat_database
WHERE datname = '$TOPIC_DB' \gx"

c 'Здесь есть много полезной информации о количестве произошедших взаимоблокировок, зафиксированных и отмененных транзакций, использовании временных файлов, ошибках подсчета контрольных сумм. Здесь же хранится статистика общего количества сеансов и количества прерванных по разным причинам сеансов.'
c 'Столбец numbackends показывает текущее количество обслуживающих процессов, подключенных к базе данных.'

p

c 'Статистика ввода-вывода на уровне сервера доступна в представлении pg_stat_io. Например, выполним контрольную точку и посмотрим количество операций чтения и записи страниц по типам процессов:'
s 1 "CHECKPOINT;"
s 1 "SELECT backend_type, sum(hits) hits, sum(reads) reads, sum(writes) writes
FROM pg_stat_io
GROUP BY backend_type;"

P 9

###############################################################################
h 'Текущие активности'

c 'Воспроизведем сценарий, в котором один процесс блокирует выполнение другого, и попробуем разобраться в ситуации с помощью системных представлений.'
c 'Создадим таблицу с одной строкой:'

s 1 'CREATE TABLE t(n integer);'
s 1 'INSERT INTO t VALUES(42);'

c 'Запустим два сеанса, один из которых изменяет таблицу и не завершает транзакцию:'

psql_open A 2 -d $TOPIC_DB
s 2 'BEGIN;'
s 2 'UPDATE t SET n = n + 1;'

c 'А второй пытается изменить ту же строку и блокируется:'

psql_open A 3 -d $TOPIC_DB
ss 3 'UPDATE t SET n = n + 2;'
sleep-ni 1

c 'Посмотрим информацию об обслуживающих процессах:'

s 1 "SELECT pid, query, state, wait_event, wait_event_type, pg_blocking_pids(pid)
FROM pg_stat_activity
WHERE backend_type = 'client backend' \gx"

p

c 'Состояние «idle in transaction» означает, что сеанс начал транзакцию, но в настоящее время ничего не делает, а транзакция осталась незавершенной. Это может стать проблемой, если ситуация возникает систематически (например, из-за некорректной реализации приложения или из-за ошибок в драйвере), поскольку открытый сеанс удерживает снимок данных и таким образом препятствует очистке.'

c 'В арсенале администратора имеется параметр idle_in_transaction_session_timeout, позволяющий принудительно завершать сеансы, в которых транзакция простаивает больше указанного времени. Также имеется параметр idle_session_timeout — принудительно завершает сеансы, простаивающие больше указанного времени вне транзакции.'

c 'А мы покажем, как завершить блокирующий сеанс вручную. Сначала узнаем номер заблокированного процесса при помощи функции pg_blocking_pids:'

s 1 "SELECT pid AS blocked_pid
FROM pg_stat_activity
WHERE backend_type = 'client backend'
AND cardinality(pg_blocking_pids(pid)) > 0;"

BLOCKED_PID=$(psql -A -t -X -d $TOPIC_DB -c "SELECT pid as blocked_pid FROM pg_stat_activity WHERE backend_type = 'client backend' AND cardinality(pg_blocking_pids(pid)) > 0")

p

c 'Блокирующий процесс можно вычислить и без функции pg_blocking_pids, используя запросы к таблице блокировок. Запрос покажет две строки: одна транзакция получила блокировку (granted), а другая ее ожидает.'

s 1 "SELECT locktype, transactionid, pid, mode, granted
FROM pg_locks
WHERE transactionid IN (
  SELECT transactionid FROM pg_locks WHERE pid = $BLOCKED_PID AND NOT granted
);"

c 'В общем случае нужно аккуратно учитывать тип блокировки.'

p

c 'Выполнение запроса можно прервать функцией pg_cancel_backend. В нашем случае транзакция простаивает, так что просто прерываем сеанс, вызвав pg_terminate_backend:'

s 1 "SELECT pg_terminate_backend(b.pid)
FROM unnest(pg_blocking_pids($BLOCKED_PID)) AS b(pid);"

c 'Функция unnest нужна, поскольку pg_blocking_pids возвращает массив идентификаторов процессов, блокирующих искомый обслуживающий процесс. В нашем примере блокирующий процесс один, но в общем случае их может быть несколько.'
c 'Подробнее о блокировках рассказывается в курсе DBA2.'

p

c 'Проверим состояние обслуживающих процессов.'

s 1 "SELECT pid, query, state, wait_event, wait_event_type
FROM pg_stat_activity
WHERE backend_type = 'client backend' \gx"

c 'Осталось только два, причем заблокированный успешно завершил транзакцию.'

p

c 'Представление pg_stat_activity показывает информацию не только про обслуживающие процессы, но и про служебные фоновые процессы экземпляра:'

s 1 "SELECT pid, backend_type, backend_start, state
FROM pg_stat_activity;"

p

c 'Сравним с тем, что показывает операционная система:'

e "sudo head -n 1 $PGDATA_A/postmaster.pid"
e "ps -o pid,command --ppid $(sudo head -n 1 $PGDATA_A/postmaster.pid)"

P 17
###############################################################################
h 'Анализ журнала'

c 'Посмотрим самый простой случай. Например, нас интересуют сообщения FATAL:'

e "sudo grep FATAL $LOG_A | tail -n 10"

c 'Сообщение «terminating connection» вызвано тем, что мы завершали блокирующий процесс.'

p

c 'Обычное применение журнала — анализ наиболее продолжительных запросов. Включим вывод всех команд и времени их выполнения:'

s 1 "ALTER SYSTEM SET log_min_duration_statement=0;"
s 1 "SELECT pg_reload_conf();"

c 'Теперь выполним какую-нибудь команду:'

s 1 'SELECT sum(random()) FROM generate_series(1,1_000_000);'

c 'И посмотрим журнал:'

e "sudo tail -n 1 $LOG_A"

###############################################################################
stop_here
cleanup
demo_end
