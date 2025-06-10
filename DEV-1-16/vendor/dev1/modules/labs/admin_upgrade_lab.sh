#!/bin/bash

. ../lib

init

export PGCONF_N=/etc/postgresql/$VERSION_N/$CLUSTER_N
export PGCONF_O=/etc/postgresql/$VERSION_O/$CLUSTER_O

sudo rm -f $H/dump.sql

start_here

###############################################################################
h '1. Пользователь и аутентификация в кластере 15'

c 'Остановим основной кластер, чтобы случайно к нему не подключиться, и запустим кластер 15 prod:'
pgctl_stop A
pgctl_start O
e pg_lsclusters

psql_open O 2 -U postgres

c 'Пользователь dbuser:'

s 2 "CREATE USER dbuser PASSWORD 'mypassword';"

c 'Добавляем в начало pg_hba.conf правило для нового пользователя:'

e "sudo sed -i '1s/^/local all dbuser scram-sha-256\n/' $PGCONF_O/pg_hba.conf"

s 2 "SELECT pg_reload_conf();"

c 'Вот что получилось:'

e "sudo egrep '^[^#]' $PGCONF_O/pg_hba.conf"

c 'Добавим пароль в .pgpass, чтобы не вводить его вручную (при выполнении задания этот шаг лучше пропустить: будет непонятно, срабатывает аутентификация по паролю или безусловный доступ, включенный по умолчанию).'

e "echo '*:*:*:dbuser:mypassword' > ~/.pgpass"
e "chmod 0600 ~/.pgpass"

###############################################################################
h '2. Таблица в кластере 15'

c 'Сначала создадим базу данных.'

s 2 "CREATE DATABASE $TOPIC_DB;"
s 2 "\c $TOPIC_DB"

c 'Тип данных uom доступен в расширении uom, установим версию 1.1.'
e "sudo make install -C $UOMDIR PG_CONFIG=${BINPATH_O}pg_config"
s 2 "CREATE EXTENSION uom VERSION '1.1';"

c 'Вспомним, что для создания таблицы пользователю понадобится право CREATE на схему. Суперпользователь должен предоставить ему это право:'

s 2 'GRANT CREATE ON SCHEMA public TO dbuser;'

c 'В сеансе пользователя dbuser создадим таблицу.'

psql_open O 3 -h localhost -U dbuser -d $TOPIC_DB
s 3 'CREATE TABLE test(id serial, length uom);'
s 3 "INSERT INTO test(length) VALUES ((500,'км')::uom);"
s 3 "INSERT INTO test(length) VALUES ((8,'мм')::uom);"

###############################################################################
h '3. Логическая резервная копия'

e "${BINPATH_O}pg_dumpall -U postgres -p $PORT_O > ~/dump.sql"

c 'Добавим табличное пространство по умолчанию:'

e "grep 'CREATE DATABASE $TOPIC_DB' ~/dump.sql"

e "sed -i 's/\(CREATE DATABASE $TOPIC_DB WITH\)/\1 TABLESPACE = ts/' ~/dump.sql"

e "grep 'CREATE DATABASE $TOPIC_DB' ~/dump.sql"

c 'Останавливаем сервер.'

pgctl_stop O

###############################################################################
h '3. Обновление на версию 16'

c 'Настройки postgresql.conf не переносим, хотя в реальной жизни это, конечно, необходимо.'

c 'Изменяем pg_hba.conf так же, как для версии 15:'

e "sudo sed -i '1s/^/local all dbuser scram-sha-256\n/' $PGCONF_N/pg_hba.conf"

p

c 'Создаем каталог для табличного пространства.'

e "sudo rm -rf $H/ts_dir"
e "sudo mkdir $H/ts_dir"
e "sudo chown postgres: $H/ts_dir"

c 'Стартуем кластер 16 и создаем табличное пространство от имени суперпользователя.'

pgctl_start N
psql_open N 2 -U postgres
s 2 "CREATE TABLESPACE ts LOCATION '$H/ts_dir';"

p

c 'Устанавливаем расширение:'
e "sudo make install -C $UOMDIR PG_CONFIG=${BINPATH_N}pg_config"

c 'Восстанавливаем кластер из резервной копии:'
e "sudo mv ~/dump.sql $H/"
s 2 "\i $H/dump.sql"

c 'При создании роли postgres выдается ошибка, поскольку такая роль уже существует; это нормально.'

###############################################################################
h '4. Проверка работоспособности'

psql_open N 3 -h localhost -p $PORT_N -U dbuser -d $TOPIC_DB

s 3 '\conninfo'
s 3 "SHOW server_version;"
s 3 "\dx uom"
s 3 "SELECT * from test;"
s 3 "SELECT pg_relation_filepath('test');"

###############################################################################

stop_here
cleanup
