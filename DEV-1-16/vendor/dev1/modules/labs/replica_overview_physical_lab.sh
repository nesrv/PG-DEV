#!/bin/bash

. ../lib

init
start_here ...

###############################################################################
h '1. Синхронная репликация'

c 'Разворачиваем реплику, как было показано в демонстрации:'

backup_dir=/home/student/tmp/backup
e "pg_basebackup --pgdata=${backup_dir} -R --checkpoint=fast"
pgctl_stop R
e "sudo rm -rf $PGDATA_R"
e "sudo mv ${backup_dir} $PGDATA_R"
e "sudo chown -R postgres: $PGDATA_R"

c 'Запускаем реплику.'
pgctl_start R

c 'Настроим синхронную репликацию на мастере. По умолчанию cинхронный режим включен, '\
'но записи о фиксации транзакций синхронизируются только с локальной файловой системой:'
s 1 "SHOW synchronous_commit;"

c 'А синхронизация с репликой не настроена:'
s 1 "SHOW synchronous_standby_names;"

c 'Реплик может быть несколько, и мастер должен знать, с какой из них синхронизироваться. '\
'Реплика представляется именем, заданным в ее параметре cluster_name:'

psql_open R 2
s 2 "SHOW cluster_name;"

s 1 "ALTER SYSTEM SET synchronous_standby_names = '\"16/replica\"';"
s 1 "SELECT pg_reload_conf();"

s 1 'SELECT sync_state FROM pg_stat_replication;'

c 'Репликация стала синхронной.'
p

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Теперь остановим реплику...'

pgctl_stop R

c '...и попробуем выполнить какую-либо транзакцию:'

ss 1 "CREATE TABLE test(n integer);"

c 'Управление возвратится только когда реплика будет снова запущена и репликация восстановится:'

pgctl_start R

r 1

###############################################################################
h '2. Конфликтующие записи'

psql_open R 2 -d $TOPIC_DB

c 'Отключаем откладывание применения конфликтующих записей:'

s 2 "ALTER SYSTEM SET max_standby_streaming_delay = 0;"
s 2 "SELECT pg_reload_conf();"

c 'Добавляем строки в таблицу:'

s 1 "INSERT INTO test(n) SELECT id FROM generate_series(1,10) AS id;"

c 'Выполняем на реплике долгий запрос...'

ss 2 "SELECT pg_sleep(5), count(*) FROM test;"

c '...а в это время на мастере удаляем строки из таблицы и выполняем очистку:'

si 1 "DELETE FROM test;"
si 1 "VACUUM VERBOSE test;"

c 'Очистка стерла все версии строк (10 removed). В итоге запрос на реплике завершается ошибкой:'

r 2

p

c 'Повторим эксперимент со включенной обратной связью.'

s 2 "ALTER SYSTEM SET hot_standby_feedback = on;"
s 2 "SELECT pg_reload_conf();"

s 1 "INSERT INTO test(n) SELECT id FROM generate_series(1,10) AS id;"

ss 2 "SELECT pg_sleep(5), count(*) FROM test;"

si 1 "DELETE FROM test;"
si 1 "VACUUM VERBOSE test;"

c 'Теперь очистка не удаляет версии строк, поскольку знает о запросе, выполняющемся на реплике (10 are dead but not yet removable
) и запрос отрабатывает:'

r 2

c 'Итак:'
ul 'В первом случае (max_standby_streaming_delay) откладывается воспроизведение журнальных записей на реплике.'
ul 'Во втором случае (hot_standby_feedback) откладывается очистка на мастере.'

c 'Отключим синхронную репликацию.'
s 1 'ALTER SYSTEM RESET synchronous_standby_names;'
s 1 'SELECT pg_reload_conf();'


###############################################################################
stop_here
cleanup
demo_end
