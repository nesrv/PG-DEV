#!/bin/bash

. ../lib

init
start_here
###############################################################################
h '1.Физическая потоковая репликация в синхронном режиме'

s 1 "CREATE DATABASE $TOPIC_DB;"

c 'Создаем и запускаем реплику точно так же, как в демонстрации.'
s 1 "\c $TOPIC_DB postgres"

c 'Резервная копия:'
pgctl_stop B
e "sudo -u postgres rm -rf $PGDATA_B"
e "sudo -u postgres pg_basebackup -D $PGDATA_B --checkpoint=fast -R --slot=replica --create-slot"

c 'В postgresql.auto.conf добавляем параметр cluster_name, чтобы основной сервер мог идентифицировать реплику:'
e "echo 'cluster_name=beta' | sudo -u postgres tee -a $PGDATA_B/postgresql.auto.conf"

c 'Другой вариант - добавить атрибут application_name в строку соединения:'
c "primary_conninfo='user=student port=5432 application_name=beta'"

c 'Перед стартом реплики уменьшим ограничение на время разрешения конфликта при потоковой репликации перед отменой запроса на реплике. Изменение значения по умолчанию (30 секунд) требует рестарт сервера, поэтому установим этот параметр заранее.'
e "echo max_standby_streaming_delay = '10s' | sudo -u postgres tee -a $PGDATA_B/postgresql.auto.conf"

e "sudo cat $PGDATA_B/postgresql.auto.conf"

pgctl_start B

p

c 'Теперь включаем на мастере режим синхронной репликации.'
s 1 "ALTER SYSTEM SET synchronous_commit = on;"
s 1 "ALTER SYSTEM SET synchronous_standby_names = beta;"

c 'Если все реплики синхронные, можно задавать synchronous_standby_names =*'
pgctl_reload A

###############################################################################
h '2.Проверка физической репликации'

s 1 'SELECT * FROM pg_stat_replication \gx'
c 'sync_state: sync говорит о том, что репликация работает в синхронном режиме.'
c 'application_name: beta - имя, под которым мастер знает реплику.'

c 'Остановим реплику.'

pgctl_stop B

s 1 "\c - student"

s 1 'BEGIN;'
s 1 'CREATE TABLE test(id integer);'
ss 1 'COMMIT;'

c 'Фиксация ждет появления синхронной реплики...'
pgctl_start B
sleep 1

c 'После старта реплики фиксация завершается.'
r 1

###############################################################################
h '3.Отмена запроса из-за очистки на мастере'

s 1 "INSERT INTO test VALUES (1);"

psql_open B 2 -p 5433 -d $TOPIC_DB -U postgres

c 'Пусть в журнал отчета сервера печатаются сообщения о конфликтах восстановления процессом startup, которые будут записываться при превышении времени ожидания значения параметра deadlock_timeout.'
s 2 '\dconfig deadlock_timeout'

c 'Для этого установим параметр log_recovery_conflict_waits.'
s 2 "ALTER SYSTEM SET log_recovery_conflict_waits = on;"
s 2 "SELECT pg_reload_conf();"

c 'Начинаем транзакцию с уровнем изоляции repeatable read: первый оператор создаст снимок данных, который будет использоваться всеми последующими операторами этой транзакции.'
s 2 "\c - student"
s 2 "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;"
s 2 "SELECT * FROM test;"

c 'На мастере изменяем единственную строку и выполняем очистку. При этом первая версия строки будет удалена.'
s 1 "UPDATE test SET id = 2;"
s 1 "VACUUM test;"

sleep 5

c 'Через 5 секунд запрос на реплике еще сработает — реплика задерживает применение конфликтующей журнальной записи:'
s 2 "SELECT * FROM test;"

c 'А в журнале отчета сервера уже есть сообщение об ожидании разрешения конфликта:'
e "sudo -u postgres tail -3 $LOG_B"

c 'Еще через 5 секунд такой же запрос уже будет аварийно прерван, поскольку версия строки, входящая в снимок, больше не существует.'

sleep 5

tolerate_lostconn=true
s 2 "SELECT * FROM test;"
tolerate_lostconn=false

###############################################################################
h '4.Запрет откладывания применения конфликтующей записи'

c 'Выставим задержку применения конфликтующих изменений в ноль.'
psql_open B 2 -p 5433 -d $TOPIC_DB -U postgres
s 2 "ALTER SYSTEM SET max_standby_streaming_delay = 0;"
s 2 "\c $TOPIC_DB student"
pgctl_reload B

c 'Снова начинаем транзакцию...'
s 2 "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;"
s 2 "SELECT * FROM test;"

c 'На мастере изменяем строку и выполняем очистку...'
s 1 "UPDATE test SET id = 3;"
s 1 "VACUUM test;"

sleep 1

c 'Запрос на реплике прерывается тут же:'

tolerate_lostconn=true
s 2 "SELECT * FROM test;"
tolerate_lostconn=false

###############################################################################
h '5.Обратная связь'

c 'Установим обратную связь и, чтобы не ждать долго, небольшой интервал оповещений.'
psql_open B 2 -p 5433 -d $TOPIC_DB -U postgres
s 2 "ALTER SYSTEM SET hot_standby_feedback = on;"
s 2 "ALTER SYSTEM SET wal_receiver_status_interval = '1s';"
s 2 "\c - student"
pgctl_reload B

c 'Снова начинаем транзакцию...'
s 2 "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;"
s 2 "SELECT * FROM test;"

c 'На мастере изменяем строку и выполняем очистку...'
s 1 "UPDATE test SET id = 4;"
s 1 "VACUUM VERBOSE test;"

c 'Благодаря обратной связи, очистка не может удалить старую версию строки (found 0 removable, 2 nonremovable row versions).'
s 2 "SELECT * FROM test;"
s 2 "COMMIT;"

sleep 2

s 1 "VACUUM VERBOSE test;"

c 'После завершения транзакции на реплике мастер может выполнить очистку (found 1 removable...). Журнальные записи реплицируются, но ничего не поломают.'

###############################################################################
h '6.Влияние слота на очистку при остановленной реплике.'

c 'Теперь отменим синхронизацию и остановим реплику:'
s 1 "\c - postgres"
s 1 "ALTER SYSTEM RESET synchronous_standby_names;"
s 1 "\c - student"
pgctl_reload A
pgctl_stop B

c 'Еще раз изменим строку таблицы:'

s 1 "UPDATE test SET id = 5;"
c 'Слот неактивен, но помнит минимальный xmin снимков реплики:'
s 1 "SELECT active, xmin FROM pg_replication_slots;"

c 'Это значение xmin меньше, чем минимальный xmin локальных снимков:'
s 1 "SELECT min(backend_xmin::text::numeric) FROM pg_stat_activity;"

c 'Поэтому слот будет задерживать очистку (1 dead row versions cannot be removed yet, oldest xmin: ...).'
s 1 "VACUUM VERBOSE test;"

c 'Удалим слот, теперь очистка сработает.'
s 1 "SELECT pg_drop_replication_slot('replica');"
s 1 "VACUUM VERBOSE test;"

###############################################################################
stop_here
cleanup
demo_end
