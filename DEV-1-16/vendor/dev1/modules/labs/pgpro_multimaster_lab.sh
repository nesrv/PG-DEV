#!/bin/bash

. ../lib
init

# Подготовка узла мультимастера
prepare_mm_node() {
	local binpath_var=BINPATH_M$1
	local pgdata_var=PGDATA_M$1
	c 'Остановим экземпляр, если он работает:'
	pgctl_stop M$1
	c 'Создаем каталог PGDATA:'
	e "sudo rm -rf ${!pgdata_var}"
	e "sudo mkdir ${!pgdata_var}"
	e "sudo chown postgres: -R ${!pgdata_var}"
	c 'Инициализируем каталог данных:'
	eu postgres "${!binpath_var}initdb -U postgres -k -D ${!pgdata_var}"
	c 'Вставим первой строкой настройки аутентификации для роли multimaster_user:'
	eu postgres "sed -i '1 i\\local    replication,$TOPIC_DB     multimaster_user        trust' ${!pgdata_var}/pg_hba.conf"
	c 'Конфигурационный файл:'
	eu postgres "echo include_dir \'conf.d\' >> ${!pgdata_var}/postgresql.conf"
	eu postgres "mkdir ${!pgdata_var}/conf.d"
	# Настройки для мультимастера
	e "cat << EOF | sudo -u postgres tee ${!pgdata_var}/conf.d/multimaster.conf
	cluster_name = 'node$1'
	shared_preload_libraries = 'multimaster'
	wal_level = logical
	max_connections = 100 # значение по умолчанию
	max_prepared_transactions = 300
	max_wal_senders = 10 # значение по умолчанию
	max_replication_slots = 10 # значение по умолчанию
	wal_sender_timeout = 0
	max_worker_processes = 320
	port = 500$1
EOF" conf
	c 'Запускаем экземпляр:'
	pgctl_start M$1
	c 'Создаем роль и базу данных для мультимастера:'
	psql_open M$1 $1 -U postgres
	s $1 "CREATE USER multimaster_user WITH SUPERUSER;"
	s $1 "CREATE DATABASE $TOPIC_DB OWNER multimaster_user;"
	s $1 "\c $TOPIC_DB multimaster_user"
}

prepare_mm_node 2
prepare_mm_node 3

start_here

###############################################################################
h '1. Настройка кластера для режима работы 2+1'

c 'Остановим основной сервер.'
pgctl_stop A

c 'Инициализируем кластер из двух узлов и третий узел для рефери.'

c 'Сначала подготовим три дополнительных экземпляра сервера Postgres Pro.'

prepare_mm_node 1

c 'Аналогично нужно подготовить еще два экземпляра на портах 5002 и 5003.'
p

c 'На третьем узле добавим расширение referee:'

s 3 "CREATE EXTENSION referee;"

c 'На каждом из двух основных узлов добавим в файл конфигурации строку подключения к узлу-рефери:'

e "cat << EOF | sudo -u postgres tee -a $PGDATA_M1/conf.d/multimaster.conf
multimaster.referee_connstring = 'dbname=$TOPIC_DB user=multimaster_user port=5003'
EOF" conf
e "cat << EOF | sudo -u postgres tee -a $PGDATA_M2/conf.d/multimaster.conf
multimaster.referee_connstring = 'dbname=$TOPIC_DB user=multimaster_user port=5003'
EOF" conf

c 'Перезапустим первый и второй узлы, чтобы применить настройки:'

pgctl_stop M1
pgctl_stop M2

pgctl_start M1
psql_open M1 1 -U multimaster_user -d $TOPIC_DB

pgctl_start M2
psql_open M2 2 -U multimaster_user -d $TOPIC_DB

c 'Инициализируем кластер мультимастера.'

s 1 'CREATE EXTENSION multimaster;'

c 'Теперь запустим функцию инициализации кластера. Первый параметр — это строка подключения к текущему узлу, второй — подключение ко второму узлу:'

s 1 "SELECT mtm.init_cluster(
    'dbname=$TOPIC_DB user=multimaster_user port=5001',
   '{\"dbname=$TOPIC_DB user=multimaster_user port=5002\"}');"

wait_sql 1 "SELECT status = 'online' FROM mtm.status();"

s 1 "SELECT * FROM mtm.status();"

c 'Создадим таблицу с первичным ключом multimaster_tbl и добавим в нее несколько строк:'

s 1 "CREATE TABLE multimaster_tbl (id integer PRIMARY KEY);"

s 1 "INSERT INTO multimaster_tbl VALUES (1),(2),(3);"

c 'Проверим доступность таблицы multimaster_tbl на втором узле:'

wait_sql 2 "SELECT status = 'online' FROM mtm.status();"

s 2 "SELECT * FROM multimaster_tbl;"

p

###############################################################################
h '2. Имитация сбоя и проверка работоспособности'

c 'Имитируем отказ узла. Для этого отключим один из узлов, например, второй:'

pgctl_stop M2

wait_sql 1 "SELECT status = 'online' FROM mtm.status();"

s 1 "SELECT * FROM mtm.status();"

c 'Добавим еще несколько строк в таблицу:'

s 1 "INSERT INTO multimaster_tbl VALUES (11),(22),(33);"

c 'Оставшийся узел сохранил работоспособность.'

p

###############################################################################
h '3. Возвращение узла в строй'

c 'Вернем в строй второй узел:'

pgctl_start M2

tolerate_lostconn=true

e_fake_p "psql -p 5002 -U multimaster_user -d $TOPIC_DB"
unset PID2
until [[ -n "$PID2" ]]; do psql_open M2 2 -U multimaster_user -d $TOPIC_DB > /dev/null;  done

tolerate_lostconn=false

c 'На втором узле проверим, что таблица доступна:'

wait_sql 2 "SELECT status = 'online' FROM mtm.status();"

s 2 "SELECT * FROM multimaster_tbl;"

c 'Кластер мультимастера продолжает работать в режиме 2+1.'

###############################################################################

stop_here
cleanup

e "sudo rm -rf $PGDATA_M1"
e "sudo rm -rf $PGDATA_M2"
e "sudo rm -rf $PGDATA_M3"
