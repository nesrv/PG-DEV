#!/bin/bash

. ../lib
init

###############################################################################

psql_close 1

# Инициализируем три узла мультимастера
init_mm_node() {
	local binpath_var=BINPATH_M$1
	local pgdata_var=PGDATA_M$1
	pgctl_stop M$1
	e "sudo rm -rf ${!pgdata_var}"
	e "sudo mkdir ${!pgdata_var}"
	e "sudo chown postgres: -R ${!pgdata_var}"
	eu postgres "${!binpath_var}initdb -U postgres -k -D ${!pgdata_var}"
	eu postgres "sed -i '1 i\\local    replication,$TOPIC_DB     multimaster_user        trust' ${!pgdata_var}/pg_hba.conf"
	eu postgres "mkdir ${!pgdata_var}/conf.d"
	eu postgres "touch ${!pgdata_var}/conf.d/multimaster.conf"
	e "cat << EOF | sudo -u postgres tee -a ${!pgdata_var}/postgresql.conf
	include_dir='conf.d'
EOF"

	# Настройки для корректного запуска мультимастера
	e "cat << EOF | sudo -u postgres tee -a ${!pgdata_var}/conf.d/multimaster.conf
	cluster_name = 'node$1'
	port = 500$1
	shared_preload_libraries = 'multimaster'
	wal_level = logical
	max_connections = 100 # значение по умолчанию
	max_prepared_transactions = 300
	max_wal_senders = 10 # значение по умолчанию
	max_replication_slots = 10 # значение по умолчанию
	wal_sender_timeout = 0
	max_worker_processes = 320
EOF" conf
	pgctl_start M$1
}

init_mm_node 1
init_mm_node 2
init_mm_node 3

start_here 5

###############################################################################

h 'Подготовка сервера'

c 'Остановим основной сервер.'
pgctl_stop A

c 'В этой демонстрации часть команд выполняется от имени пользователя ОС postgres. Обратите внимание на приглашения перед командами.'

c "Для демонстрации инициализированы и настроены три экземпляра Postgres Pro Enterprise. Каталоги данных и порты:"
ul "$PGDATA_M1, порт $PORT_M1"
ul "$PGDATA_M2, порт $PORT_M2"
ul "$PGDATA_M3, порт $PORT_M3"

c 'Дополнительные параметры первого экземпляра:'
e "sudo cat $PGDATA_M1/conf.d/multimaster.conf" conf

c 'Остальные экземпляры настроены аналогично.'
p

h 'Инициализация кластера multimaster'

c 'Узлы кластера уже подготовлены, теперь необходимо инициализировать весь кластер multimaster из трех узлов:'

psql_open M1 1 -U postgres
psql_open M2 2 -U postgres
psql_open M3 3 -U postgres

c 'Подготовим роль и базу данных для работы мультимастера на каждом из узлов.'

c 'Для первого узла:'

s 1 "CREATE USER multimaster_user WITH SUPERUSER;"
s 1 "CREATE DATABASE $TOPIC_DB OWNER multimaster_user;"
s 1 "\c $TOPIC_DB multimaster_user"

c 'Для второго узла:'

s 2 "CREATE USER multimaster_user WITH SUPERUSER;"
s 2 "CREATE DATABASE $TOPIC_DB OWNER multimaster_user;"
s 2 "\c $TOPIC_DB multimaster_user"

c 'И для третьего узла:'

s 3 "CREATE USER multimaster_user WITH SUPERUSER;"
s 3 "CREATE DATABASE $TOPIC_DB OWNER multimaster_user;"
s 3 "\c $TOPIC_DB multimaster_user"

c "Теперь объединим узлы в кластер. Для этого на любом из узлов добавим расширение multimaster в БД $TOPIC_DB..."

s 1 'CREATE EXTENSION multimaster;'

c '...и запустим функцию инициализации кластера. Первый параметр — это строка подключения к текущему узлу, второй и третий — подключение к остальным узлам:'

s 1 "SELECT mtm.init_cluster(
    'dbname=$TOPIC_DB user=multimaster_user port=5001',
   '{\"dbname=$TOPIC_DB user=multimaster_user port=5002\",
     \"dbname=$TOPIC_DB user=multimaster_user port=5003\"}');"

c 'Функция возвращает пустой ответ в случае успеха, либо ошибку инициализации.'

P 8
###############################################################################

h 'Процессы'

wait_sql 1 "SELECT status = 'online' FROM mtm.status();"
wait_sql 2 "SELECT status = 'online' FROM mtm.status();"
wait_sql 3 "SELECT status = 'online' FROM mtm.status();"

c 'Посмотрим на процессы, которые запускаются на каждом узле кластера:'

e "ps -o pid,command --ppid `sudo head -n 1 $PGDATA_M1/postmaster.pid`"

c 'Количество процессов довольно велико, следует обеспечить их достаточными ресурсами.'

P 11
###############################################################################

h 'Проверка состояния кластера'

c 'Проверим статус узла кластера:'

s 1 "SELECT * FROM mtm.status();"

c 'На любом из узлов кластера можно получить список всех узлов:'

s 3 "SELECT * FROM mtm.nodes();"

c 'Проверим работу кластера — создадим таблицу на первом узле. Рекомендуется использовать таблицы с явно определенным первичным ключом — мы так и поступим. Добавим в таблицу несколько строк:'

s 1 "CREATE TABLE multimaster_tbl (id integer PRIMARY KEY);"

s 1 "INSERT INTO multimaster_tbl VALUES (1),(2),(3);"

c 'Проверим доступность таблицы multimaster_tbl на втором узле:'

wait_sql 2 "SELECT status = 'online' FROM mtm.status();"

s 2 "SELECT * FROM multimaster_tbl;"

c 'Таблица и строки доступны на втором узле — кластер работает.'

P 13
###############################################################################

h 'Отказ узла'

c 'Для демонстрации отказа узла остановим экземпляр Postgres Pro на третьем сервере:'

pgctl_stop M3

c 'Проверим доступные узлы кластера:'

wait_sql 1 "SELECT status = 'online' FROM mtm.status();"
wait_sql 2 "SELECT status = 'online' FROM mtm.status();"

s 1 "SELECT * FROM mtm.status();"

c 'Номер поколения увеличился.'

c 'Повторим запись в таблицу multimaster_tbl:'

s 2 "INSERT INTO multimaster_tbl VALUES (11),(22),(33);"

c 'Проверим корректную работу кластера — прочитаем все строки из этой таблицы на первом узле:'

s 1 "SELECT * FROM multimaster_tbl;"

c 'Добавленные строки видны: кластер продолжает работать даже при отсутствии одного из узлов.'

GEN=`s_bare 1 "SELECT gen_num FROM mtm.status();"`

P 15
###############################################################################

h 'Восстановление узла'

c 'Текущее состояние узлов кластера:'
s 1 "SELECT * FROM mtm.status();"

c 'Вернем третий узел в состав кластера. Для этого запустим экземпляр Postgres Pro на третьем узле:'

pgctl_start M3

# Команду подключения необходимо выполнить сразу после запуска узла (то есть без пауз, иначе поколение сразу будет новым)
interactive_save=$interactive
interactive=false

c 'Сразу после подключения видим, что третий узел пока что не готов к работе:'

# Эту команду выполняем без подтверждения и без пауз
psql_open M3 3 -U postgres
si 1 "SELECT * FROM mtm.status();"

interactive=$interactive_save

c 'После запуска узел подключается к кластеру, получает все необходимые изменения...'

wait_sql 1 "SELECT gen_num > $GEN AND 3 = ANY(gen_members_online) FROM mtm.status();"

c '...и возвращется в строй. Номер поколения снова увеличивается:'

s 1 "SELECT * FROM mtm.status();"

c 'Все добавленные ранее строки видны на третьем узле.'

s 3 "\c $TOPIC_DB multimaster_user"
s 3 "SELECT * FROM multimaster_tbl;"

P 17
###############################################################################

h 'Режим 2+1'

c 'Для перехода в режим работы 2+1 удалим из кластера один из узлов (третий):'

GEN=`s_bare 1 "SELECT gen_num FROM mtm.status();"`
s 3 "SELECT mtm.drop_node(3);"

# ждем, пока узел реально отключится
wait_sql 1 "SELECT gen_num > $GEN FROM mtm.status();"
#wait_sql 1 "SELECT (gen_num > $GEN) AND ARRAY[1,2] <@ gen_members_online FROM mtm.status();"

c 'На удаленном узле добавим расширение referee:'

s 3 "CREATE EXTENSION referee;"

c 'Остановим остальные два узла:'

pgctl_stop M1
pgctl_stop M2

c 'На каждом из двух узлов в файл конфигурации необходимо добавить строку подключения к узлу-рефери:'

e "cat << EOF | sudo -u postgres tee -a $PGDATA_M1/conf.d/multimaster.conf
multimaster.referee_connstring = 'dbname=$TOPIC_DB user=multimaster_user port=5003'
EOF" conf
e "cat << EOF | sudo -u postgres tee -a $PGDATA_M2/conf.d/multimaster.conf
multimaster.referee_connstring = 'dbname=$TOPIC_DB user=multimaster_user port=5003'
EOF" conf

c 'Запускаем любой из основных узлов. Например второй:'

pgctl_start M2

tolerate_lostconn=true

e_fake_p "psql -p 5002 -U multimaster_user -d $TOPIC_DB"
unset PID2
until [[ -n "$PID2" ]]; do psql_open M2 2 -U multimaster_user -d $TOPIC_DB > /dev/null;  done

c 'Запускаем другой узел:'

pgctl_start M1

e_fake_p "psql -p 5001 -U multimaster_user -d $TOPIC_DB"
unset PID1
until [[ -n "$PID1" ]]; do psql_open M1 1 -U multimaster_user -d $TOPIC_DB > /dev/null;  done

tolerate_lostconn=false

c 'Проверим статус кластера:'

wait_sql 1 "SELECT status = 'online' FROM mtm.status();"
wait_sql 2 "SELECT status = 'online' FROM mtm.status();"

s 2 "SELECT * FROM mtm.status();"

c 'Проверим также, что ранее созданная таблица на месте:'

s 2 "SELECT * FROM multimaster_tbl;"

c 'Снова добавим строки в таблицу multimaster_tbl:'

s 2 "INSERT INTO multimaster_tbl VALUES (111),(222),(333);"

s 1 "SELECT * FROM multimaster_tbl;"

c 'Кластер продолжает работать. Но он уже состоит из двух узлов и одного рефери.'

c 'Убедиться что узлы корректно взаимодействуют с рефери можно посмотрев их журналы сообщений:'

e "sudo grep referee /var/lib/pgpro/ent-16-MM-1/pgpro-ent.log"
e "sudo grep referee /var/lib/pgpro/ent-16-MM-2/pgpro-ent.log"

###############################################################################
stop_here
cleanup
e "sudo rm -rf $PGDATA_M1"
e "sudo rm -rf $PGDATA_M2"
e "sudo rm -rf $PGDATA_M3"
demo_end
