#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. База данных и роли'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 'CREATE USER writer;'
s 1 'CREATE USER reader;'

###############################################################################
h '2. Привилегии'

s 1 "\c $TOPIC_DB"
s 1 'REVOKE ALL ON SCHEMA public FROM public;'
s 1 'GRANT ALL ON SCHEMA public TO writer;'
s 1 'GRANT USAGE ON SCHEMA public TO reader;'

###############################################################################
h '3. Привилегии по умолчанию'

s 1 'ALTER DEFAULT PRIVILEGES
FOR ROLE writer
IN SCHEMA public
GRANT SELECT ON TABLES TO reader;'

###############################################################################
h '4. Пользователи'

c 'Пишущая роль:'

s 1 'CREATE ROLE w1 LOGIN IN ROLE writer;'

c 'Конструкция IN ROLE сразу же добавляет новую роль в указанную. То есть такая команда эквивалентна двум:'

s_fake 1 'CREATE ROLE w1 LOGIN;'
s_fake 1 'GRANT writer TO w1;'

c 'Читающая роль:'

s 1 'CREATE ROLE r1 LOGIN IN ROLE reader;'

local_trust=`s_bare 1 "select count(*)>0 from pg_hba_file_rules where type='local' and database=array['all'] and user_name=array['all'] and auth_method='trust';"`

if [ $local_trust == "f" ]; then
	c 'Чтобы подключаться к БД без паролей (мы их не задали для новых ролей), добавим в pg_hba.conf правило доступа и перечитаем конфигурацию:'
	e "sudo sed -i '1s/^/local   $TOPIC_DB   all   trust/' $CONF_A/pg_hba.conf"
	s 1 "SELECT type, database, user_name, auth_method
FROM pg_hba_file_rules()
WHERE database='{$TOPIC_DB}';"
	s 1 "SELECT pg_reload_conf();"
fi

###############################################################################
h '5. Таблица'

s 1 '\c - writer'
s 1 'CREATE TABLE t(n integer);'

###############################################################################
h '6. Проверка'

c 'Роль w1 может вставлять строки:'

s 1 '\c - w1'
s 1 'INSERT INTO t VALUES (42);'

c 'Роль r1 может читать таблицу:'

s 1 '\c - r1'
s 1 'SELECT * FROM t;'

c 'Но не может изменить:'

s 1 'UPDATE t SET n = n + 1;'

c 'Роль w1 может удалить таблицу:'

s 1 '\c - w1'
s 1 'DROP TABLE t;'

c 'Напомним, что в PostgreSQL начиная с версии 14 доступна предопределенная роль pg_read_all_data, автоматически дающая возможность чтения любых данных.'

c 'А удалить базу данных сможет или ее владелец, или суперпользолватель:'

s 1 "\c postgres postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################
stop_here
cleanup
demo_end
