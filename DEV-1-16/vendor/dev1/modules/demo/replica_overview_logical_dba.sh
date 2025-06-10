#!/bin/bash

. ../lib
init

###############################################################################
start_here 7
h 'Логическая репликация'

c 'Пусть на первом сервере имеется таблица:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE test(id integer PRIMARY KEY, descr text);'

c 'Склонируем кластер с помощью автономной копии, как мы делали в теме «Обзор физической репликации», но команде pg_basebackup не будем передавать ключ -R, поскольку нам потребуется независимый сервер, а не реплика.'
backup_dir=~student/tmp/backup  # очистка каталога - в init
e_fake "rm -rf $backup_dir"
e "pg_basebackup --pgdata=$backup_dir --checkpoint=fast"

c "Если второй сервер работает, остановим его."
pgctl_stop R

c "Перемещаем резервную копию в каталог данных второго сервера, поменяв владельца файлов:"
e "sudo rm -rf $PGDATA_R"
e "sudo mv $backup_dir $PGDATA_R"
e "sudo chown -R postgres: $PGDATA_R"

c "Запускаем второй сервер:"
pgctl_start R

c "Получили два независимых сервера, на каждом из них есть пустая таблица test. Добавим в таблицу на первом сервере пару строк:"

s 1 "INSERT INTO test VALUES (1, 'Раз'), (2, 'Два');"

c 'Теперь мы хотим настроить между серверами логическую репликацию. Для этого понадобится дополнительная информация в журнале публикующего сервера:'

s 1 "ALTER SYSTEM SET wal_level = logical;"
pgctl_restart A

c 'На первом сервере создаем публикацию:'

psql_open A 1 -d $TOPIC_DB
s 1 'CREATE PUBLICATION test_pub FOR TABLE test;'

s 1 '\dRp+'

c 'На втором сервере подписываемся на эту публикацию:'

psql_open R 2 -d $TOPIC_DB
s 2 "CREATE SUBSCRIPTION test_sub
CONNECTION 'port=5432 user=student dbname=$TOPIC_DB'
PUBLICATION test_pub;"

s 2 '\dRs'

c 'Проверяем репликацию:'
s 1 "INSERT INTO test VALUES (3, 'Три');"

wait_sql 2 "SELECT true FROM test WHERE id=3;"
s 2 'SELECT * FROM test;'

c 'Состояние подписки можно посмотреть в представлении:'
s 2 'SELECT * FROM pg_stat_subscription \gx'

c 'К процессам сервера-подписчика добавился logical replication worker (его номер указан в pg_stat_subscription.pid):'
e "ps -o pid,command --ppid `sudo head -n 1 $PGDATA_R/postmaster.pid`"

###############################################################################
P 9
h 'Конфликты'

c 'Локальные изменения на подписчике не запрещаются. Вставим строку в таблицу на втором сервере:'
s 2 "INSERT INTO test VALUES (4, 'Четыре (локально)');"

c 'Если теперь строку с таким же значением первичного ключа вставить на публикующем сервере, при ее применении на стороне подписки произойдет конфликт.'
s 1 "INSERT INTO test VALUES (4, 'Четыре');"
s 1 "INSERT INTO test VALUES (5, 'Пять');"

c 'Подписка не может применить изменение, репликация остановилась.'
s 2 'SELECT * FROM pg_stat_subscription \gx'
s 2 'SELECT * FROM test;'

c 'Чтобы разрешить конфликт, удалим строку на втором сервере и немного подождем...'
s 2 'DELETE FROM test WHERE id=4;'

wait_sql 2 "SELECT true FROM test WHERE id=4;"
s 2 'SELECT * FROM test;'

c 'Репликация возобновилась.'
p

###############################################################################
h 'Удаление подписки'

c 'Если репликация больше не нужна, надо аккуратно удалить подписку — иначе на публикующем сервере останется открытым репликационный слот.'
s 2 'DROP SUBSCRIPTION test_sub;'

###############################################################################
stop_here
cleanup
demo_end
