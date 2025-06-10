#!/bin/bash

. ../lib
init
start_here

###############################################################################
h '1. Репликация на одном сервере'

c 'Тестовая таблица:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE TABLE test (
    id int
);"

c 'Копия базы с таблицей:'
s 1 "\c student"
s 1 "CREATE DATABASE ${TOPIC_DB}2 TEMPLATE ${TOPIC_DB};"

c 'И установим необходимый уровень журнала:'
s 1 "ALTER SYSTEM SET wal_level = logical;"
psql_close 1
pgctl_restart A

c 'Подключаемся к базам данных:'
psql_open A 1 ${TOPIC_DB}
psql_open A 2 ${TOPIC_DB}2

c 'В первой базе создадим публикацию:'
s 1 'CREATE PUBLICATION test FOR TABLE test;'

c 'Команда CREATE SUBSCRIPTION по умолчанию создает слот репликации, а для этого дожидается завершения всех транзакций, активных на момент начала создания слота. Одной из таких транзакция является та, которая выполняет команду CREATE SUBSCRIPTION, что приводит к бесконечному ожиданию.'

c 'Проблема решается созданием слота вручную и указанием его имени при создании подписки:'
s 1 "SELECT pg_create_logical_replication_slot('test_slot','pgoutput');"
s 2 "CREATE SUBSCRIPTION test
CONNECTION 'user=student dbname=${TOPIC_DB}'
PUBLICATION test WITH (slot_name = test_slot, create_slot = false);"

p

c 'Проверим:'
s 1 "INSERT INTO test SELECT * FROM generate_series(1,100);"

wait_sql 2 "SELECT count(*)=100 FROM test;"
s 2 "SELECT count(*) FROM test;"

c 'Репликация работает.'

p

c 'Удалим публикацию, подписку и вторую базу данных.'
s 1 "DROP PUBLICATION test;"
s 2 "DROP SUBSCRIPTION test;"
s 1 "DROP DATABASE ${TOPIC_DB}2 (FORCE);"

###############################################################################
h '2. Двунаправленная репликация'

c "Клонируем сервер с помощью резервной копии:"
backup_dir=/home/student/tmp/backup # очищается при сбросе
e "pg_basebackup --pgdata=${backup_dir} --checkpoint=fast"

c "Убеждаемся, что второй сервер остановлен, и выкладываем резервную копию:"
pgctl_stop R
e "sudo rm -rf $PGDATA_R"
e "sudo mv ${backup_dir} $PGDATA_R"
e "sudo chown -R postgres: $PGDATA_R"

c "Запускаем второй сервер:"
pgctl_start R

c "База данных с таблицей и настройка уровня журнала также были склонированы:"
psql_open R 2 ${TOPIC_DB}
s 2 "SHOW wal_level;"
s 2 "SELECT count(*) FROM test;"

c "Публикуем таблицу на обоих серверах:"
s 1 'CREATE PUBLICATION test FOR TABLE test;'
s 2 'CREATE PUBLICATION test FOR TABLE test;'

c "Подписываемся:"
s 1 "CREATE SUBSCRIPTION test
CONNECTION 'port=$PORT_R user=student dbname=${TOPIC_DB}'
PUBLICATION test WITH (copy_data = false, origin = none);"

s 2 "CREATE SUBSCRIPTION test
CONNECTION 'port=$PORT_A user=student dbname=${TOPIC_DB}'
PUBLICATION test WITH (copy_data = false, origin = none);"

c 'Изменяем строки таблицы:'
s 1 "UPDATE test SET id = id + 100;"

c 'Чтобы изменения и удаления реплицировались, нужно задать идентификацию строк. По умолчанию строки идентифицируются по первичному ключу.'

s 1 'ALTER TABLE test ADD PRIMARY KEY (id);'
s 2 'ALTER TABLE test ADD PRIMARY KEY (id);'

c 'Повторяем попытку:'
si 1 "UPDATE test SET id = id + 100;"
si 2 "UPDATE test SET id = id + 100;"

c 'Смотрим результат:'
s 1 'SELECT min(id), max(id) FROM test;'
s 2 'SELECT min(id), max(id) FROM test;'

###############################################################################
stop_here
cleanup
demo_end
