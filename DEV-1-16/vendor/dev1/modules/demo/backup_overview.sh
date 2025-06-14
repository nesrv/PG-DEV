#!/bin/bash


. ../lib

init

start_here 6

###############################################################################
h 'COPY'

c 'Создадим базу данных и таблицу в ней.'
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE t(id numeric, s text);'
s 1 "INSERT INTO t VALUES (1, 'Привет!'), (2, ''), (3, NULL);"

s 1 'SELECT * FROM t;'

c 'Вот как выглядит таблица в выводе команды COPY:'
s 1 'COPY t TO STDOUT;'

c 'Обратите внимание на то, что пустая строка и NULL — разные значения, хотя, выполняя запрос, этого и не заметно.'
p

c 'Аналогично можно вводить данные:'
s 1 'TRUNCATE TABLE t;'
s 1 'COPY t FROM STDIN;
1	Hi there!
2	
3	\N
\.'

c 'Проверим:'
s 1 "\pset null '<null>'"
s 1 'SELECT * FROM t;'

P 9

###############################################################################
h 'Утилита pg_dump'

c 'Посмотрим на результат работы утилиты pg_dump в простом формате (plain). Обратите внимание на то, в каком виде сохранены данные из таблицы.'
c 'Если в шаблон template1 вносились какие-либо изменения, они также попадут в резервную копию. Поэтому при восстановлении базы данных имеет смысл предварительно создать ее из шаблона template0 (указанный ключ --create добавляет нужные команды автоматически).'

e "pg_dump -d $TOPIC_DB --create" pgsql

p

c 'В качестве примера использования скопируем таблицу в другую базу.'
s 1 "CREATE DATABASE ${TOPIC_DB}2;"

e "pg_dump -d $TOPIC_DB --table=t | psql -d ${TOPIC_DB}2"

psql_open A 2 -d ${TOPIC_DB}2
s 2 'SELECT * FROM t;'
#psql_close 2

P 16

###############################################################################
h 'Автономная резервная копия'

c 'Значения параметров по умолчанию позволяют использовать протокол репликации:'
s 1 "SELECT name, setting
FROM pg_settings
WHERE name IN ('wal_level','max_wal_senders');"

p

c 'Разрешение на локальное подключение по протоколу репликации в pg_hba.conf также прописано по умолчанию (хотя это и зависит от конкретной пакетной сборки):'
s 1 "SELECT type, database, user_name, address, auth_method 
FROM pg_hba_file_rules() 
WHERE 'replication' = ANY(database);"

p

c 'Еще один кластер баз данных replica был предварительно инициализирован на порту 5433. Убедимся, что кластер остановлен, с помощью утилиты пакета для Ubuntu:'
e 'pg_lsclusters'

p

c 'Создадим резервную копию. Используем формат по умолчанию (plain):'
e "rm -rf /home/student/tmp/basebackup"
e "pg_basebackup --pgdata=/home/student/tmp/basebackup --checkpoint=fast"

c 'Утилита pg_basebackup сразу после подключения к серверу выполняет контрольную точку. По умолчанию грязные буферы записываются постепенно, чтобы не создавать пиковую нагрузку (запись длится до 4,5 минут). Если указать --checkpoint=fast, буферы записываются без пауз.'

P 18

###############################################################################
h 'Восстановление'

c 'Заменим каталог кластера replica созданной копией, предварительно убедившись, что кластер остановлен:'
pgctl_status R
e "sudo rm -rf $PGDATA_R"
e "sudo mv /home/student/tmp/basebackup/ $PGDATA_R"

c 'Файлы кластера должны принадлежать пользователю postgres.'
e "sudo chown -R postgres:postgres $PGDATA_R"

c 'Проверим содержимое каталога:'
e "sudo ls -l $PGDATA_R"

p

c 'В процессе запуска произойдет восстановление из резервной копии.'
pgctl_start R

c 'Теперь оба сервера работают одновременно и независимо.'
c 'Основной сервер:'
s 1 "INSERT INTO t VALUES (4, 'Основной сервер');"
s 1 "SELECT * FROM t;"

c 'Сервер, восстановленный из резервной копии:'
psql_open R 2 -d $TOPIC_DB
s 2 "INSERT INTO t VALUES (4, 'Резервная копия');"
s 2 "SELECT * FROM t;"

###############################################################################
stop_here
pgctl_stop R
cleanup
demo_end
