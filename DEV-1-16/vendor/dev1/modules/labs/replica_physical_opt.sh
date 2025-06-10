#!/bin/bash

. ../lib

init
start_here
###############################################################################
h '1.Физическая потоковая репликация + архив WAL'

c 'Включим прослушивание всех интерфейсов сервером и настроим работу в режиме архивирования WAL.'
s 1 "\c - postgres"
s 1 "ALTER SYSTEM SET listen_addresses = '*';"
s 1 "ALTER SYSTEM SET archive_mode = on;"
s 1 "ALTER SYSTEM SET archive_timeout = '30s';"
s 1 "ALTER SYSTEM SET archive_command = '[ -f $H/archive/%f ] || cp %p $H/archive/%f';"

c 'Архив WAL'
e "sudo -u postgres mkdir $H/archive"

c 'Разрешения в HBA.'
e "sudo -u postgres sed -i.bak 's/127\.0\.0\.1\/32/samenet/' $CONF_A/pg_hba.conf"

c 'Виртуальный сетевой интерфейс. Если у Вас уже используется сеть 192.168.255.0/24, то назначьте виртуальному сетевому интерфейсу иной IPv4 адрес по Вашему выбору.'
# Удалим виртуальный сетевой интерфейс, если он существует.
ip l show dummy0 >& /dev/null && sudo ip l delete dummy0
e "sudo ip l add dummy0 type dummy"
e "sudo ip a add 192.168.255.1/24 dev dummy0"
e "ping -c1 192.168.255.1"

pgctl_restart A

c 'Резервная копия:'
pgctl_stop B
e "sudo -u postgres rm -rf $PGDATA_B"
e "sudo -u postgres pg_basebackup -D $PGDATA_B --checkpoint=fast"

c 'В postgresql.auto.conf добавляем параметр cluster_name, чтобы основной сервер мог идентифицировать реплику:'
e "echo 'cluster_name=beta' | sudo -u postgres tee -a $PGDATA_B/postgresql.auto.conf"
e "echo \"restore_command = 'cp $H/archive/%f %p'\" | sudo -u postgres tee -a $PGDATA_B/postgresql.auto.conf"
e "echo \"primary_conninfo = 'user=postgres password=postgres host=192.168.255.1 port=5432'\" | sudo -u postgres tee -a $PGDATA_B/postgresql.auto.conf"

e "sudo cat $PGDATA_B/postgresql.auto.conf"

e "sudo -u postgres touch $PGDATA_B/standby.signal"
pgctl_start B

###############################################################################
h '2.Проверка репликации'

s 1 "\c - student"
s 1 "CREATE DATABASE $TOPIC_DB;"

s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE test(s text);'
s 1 "INSERT INTO test VALUES ('Привет, мир!');"

c 'Пока задержки репликации не наблюдается.'
s 1 'SELECT * FROM pg_stat_replication \gx'

psql_open B 2 -p 5433
wait_db 2 $TOPIC_DB
s 2 "\c $TOPIC_DB"

wait_sql 2 "select true from pg_tables where tablename='test';"
wait_sql 2 "select count(*)=1 from test;"

s 2 'SELECT * FROM test;'

###############################################################################
h '3.Отказ сети'

c 'Удаляем сетевой интерфейс - авария сети.'
e "sudo ip l delete dummy0"
e "ping -c1 192.168.255.1"

c 'На мастере изменяем данные.'
s 1 "INSERT INTO test VALUES ('Сетевая авария.');"

c 'Данные не реплицированы.'
s 2 'SELECT * FROM test;'

c 'Заметно задержку репликации.'
s 1 'SELECT * FROM pg_stat_replication \gx'

c 'Но архивация продолжает работать.'
s 1 'SELECT * FROM pg_stat_archiver \gx'

c 'Переключим сегмент WAL.'
s 1 '\c - postgres'
s 1 'SELECT pg_switch_wal();'
s 1 "INSERT INTO test VALUES ('Сегмент WAL переключен.');"

c 'Подождем, когда реплика получит изменения с мастера, выполненные до переключения сегмента.'
wait_sql 2 "select count(*)>1 from test;" 60
s 2 'SELECT * FROM test;'

###############################################################################
h '4.Восстановление сети'

c 'На мастере изменяем данные.'
s 1 "INSERT INTO test VALUES ('Сеть еще неисправна...');"

c 'Данные не реплицированы.'
s 2 'SELECT * FROM test;'

c 'Восстановим сетевой интерфейс.'
e "sudo ip l add dummy0 type dummy"
e "sudo ip a add 192.168.255.1/24 dev dummy0"
e "ping -c1 192.168.255.1"

c 'На мастере изменяем данные.'
s 1 "INSERT INTO test VALUES ('Сеть восстановлена!');"

s 1 'SELECT * FROM pg_stat_replication \gx'

wait_sql 2 "select count(*)>2 from test;"

c 'Данные реплицированы.'
s 2 'SELECT * FROM test;'

p

###############################################################################
stop_here
cleanup
ip l show dummy0 >& /dev/null && sudo ip l delete dummy0
demo_end
