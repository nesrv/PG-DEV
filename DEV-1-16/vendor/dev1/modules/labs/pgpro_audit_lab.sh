#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Запись сообщений аудита и в CSV и в syslog'

c 'Создадим базу данных.'
s 1 "CREATE DATABASE $TOPIC_DB;"

c 'Загрузка библиотеки:'
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_proaudit';"

c 'Подключение библиотеки требует перезагрузки СУБД.'
pgctl_restart A
psql_open A 1 -d $TOPIC_DB

c 'Создадим расширение pg_proaudit:'
s 1 "CREATE EXTENSION pg_proaudit;"

c 'Настройка записи сообщений аудита одновременно в CSV файл и в syslog:'
s 1 "ALTER SYSTEM SET pg_proaudit.log_destination = 'csvlog,syslog';"

c 'Установка имени программы — идентификатора в записях syslog:'
s 1 "ALTER SYSTEM SET syslog_ident = 'MY_audit';"
s 1 "SELECT pg_reload_conf();"
c 'Наличие идентификатора облегчит поиск записей аудита в журнале сообщений.'

p

###############################################################################
h '2. Аудит регистрации пользователей и создания новых таблиц'

c 'Аудит на все события, связанные с управлением ролями:'
s 1 "SELECT pg_proaudit_set_rule(current_database(), 'ALL', 'ROLE', NULL, NULL);"

c 'Аудит событий создания таблиц:'
s 1 "SELECT pg_proaudit_set_rule(current_database(), 'CREATE TABLE', 'TABLE', NULL, NULL);"

c 'Получившиеся настройки аудита:'
s 1 'SELECT * FROM pg_proaudit_settings;'

p

###############################################################################

h '3. Регистрация событий создания и управления пользователями'

c 'Регистрация нового пользователя:'
s 1 "CREATE ROLE observed1 LOGIN PASSWORD 'obs123';"

c 'Второй сеанс от имени observed1:'
psql_open A 2 "'dbname=$TOPIC_DB user=observed1 password=obs123'"

c 'Командой ls -ltr $PGDATA/pg_proaudit можно получить сортированный по времени модификации список файлов аудита.'
sleep-ni 1
e "sudo ls -ltr $PGDATA/pg_proaudit"

c 'Проверяем CSV-файл аудита, который был изменен последним:'
file_aud=$(sudo ls -tr $PGDATA/pg_proaudit| tail -1)
e "sudo tail -1 $PGDATA/pg_proaudit/${file_aud}"

c 'Получите последние две записи в журнале /var/log/syslog по установленному идентификатору MY_audit:'
e "sudo grep MY_audit /var/log/syslog | tail -2"

p

###############################################################################

h '4. Создание таблицы и предоставление прав на нее'

c 'Суперпользователь student создает таблицу и выдает на нее права observed1.'

# Для удобства вывода в syslog команды SQL пишу в одну строку.
s 1 'CREATE TABLE tab1(n integer, txt text);'
s 1 'GRANT SELECT,INSERT,UPDATE,DELETE ON tab1 TO observed1;'

c 'Проверяем CSV-файл аудита: должно быть видно CREATE TABLE, но не GRANT.'
sleep-ni 1
file_aud=$(sudo ls -tr $PGDATA/pg_proaudit| tail -1)
e "sudo tail -2 $PGDATA/pg_proaudit/${file_aud}"

c 'Поиск записей в журнале /var/log/syslog по установленному идентификатору MY_audit:'
e "sudo grep MY_audit /var/log/syslog | tail -4"

p

###############################################################################

h '5. Регистрация команд DML с таблицей tab1'

c 'Установка регистрации команд DML для tab1.'

#s 1 "SELECT pg_proaudit_set_object('SELECT', 'tab1'::regclass);"
s 1 "SELECT pg_proaudit_set_rule(current_database(), 'SELECT', 'TABLE', 'public.tab1', NULL);"
#s 1 "SELECT pg_proaudit_set_object('INSERT', 'tab1'::regclass);"
s 1 "SELECT pg_proaudit_set_rule(current_database(), 'INSERT', 'TABLE', 'public.tab1', NULL);"
#s 1 "SELECT pg_proaudit_set_object('UPDATE', 'tab1'::regclass);"
s 1 "SELECT pg_proaudit_set_rule(current_database(), 'UPDATE', 'TABLE', 'public.tab1', NULL);"
#s 1 "SELECT pg_proaudit_set_object('DELETE', 'tab1'::regclass);"
s 1 "SELECT pg_proaudit_set_rule(current_database(), 'DELETE', 'TABLE', 'public.tab1', NULL);"

c 'Получившиеся настройки аудита:'
s 1 'SELECT * FROM pg_proaudit_settings;'

c 'Команды в сеансе observed1:'

s 2 "INSERT INTO tab1 VALUES (1, 'Один');"
s 2 "SELECT * FROM tab1;"
s 2 "UPDATE tab1 SET n=2;"
s 2 "DELETE FROM tab1;"

c 'Проверяем CSV-файл аудита:'
sleep-ni 1
file_aud=$(sudo ls -tr $PGDATA/pg_proaudit| tail -1)
e "sudo tail -4 $PGDATA/pg_proaudit/${file_aud}"

c 'Поиск записей в журнале /var/log/syslog по установленному идентификатору MY_audit:'
e "sudo grep MY_audit /var/log/syslog | tail -8"
p

###############################################################################

stop_here
cleanup
