#!/bin/bash

. ../lib
init

start_here 4

###############################################################################
h 'Установка расширения pg_proaudit'

c 'Создадим базу данных.'
s 1 "CREATE DATABASE $TOPIC_DB;"

c 'Расширение pg_proaudit требует загрузки одноименной разделяемой библиотеки:'
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_proaudit';"

c 'Необходимо рестартовать СУБД.'
pgctl_restart A
psql_open A 1 -d $TOPIC_DB

c 'Создадим расширение pg_proaudit:'
s 1 "CREATE EXTENSION pg_proaudit;"

c 'В результате в списке процессов экземпляра должен быть виден процесс pg_proaudit.'
e 'ps f -C postgres'

P 7
###############################################################################
h 'Аудит ролей и объектов'

c 'Включим аудит на все события, связанные с управлением ролями — для текущей базы, для всех объектов и всех ролей:'
s 1 "SELECT pg_proaudit_set_rule(
  db_name => current_database(),
  event_type => 'ALL',
  object_type => 'ROLE',
  object_name => NULL,
  role_name => NULL
);"

c 'Аудит включается немедленно.'
c 'Зарегистрируем нового пользователя и отдельной командой дадим право начинать сеанс.'
s 1 "CREATE ROLE alice;"
s 1 "ALTER ROLE alice LOGIN;"

c 'А теперь назначим пользователю пароль:'
s 1 "ALTER ROLE alice PASSWORD 'alice';"

c 'Представление pg_proaudit_settings используется для проверки настроек аудита:'
s 1 'SELECT * FROM pg_proaudit_settings;'

c 'Ожидаем, что в протокол аудита попали три записи. Проверим с помощью команды, выводящей последние три строки из файла протокола, имеющего самую свежую дату модификации.'
sleep-ni 1
file_prot=$(sudo ls -tr $PGDATA/pg_proaudit| tail -1)
e "sudo tail -3 ${PGDATA}/pg_proaudit/${file_prot}"

p

c 'Включим аудит событий подключения. Здесь функции pg_proaudit_set_rule вместо типа объекта передаем NULL.'
s 1 "SELECT pg_proaudit_set_rule(
  db_name => current_database(),
  event_type => 'AUTHENTICATE',
  object_type => NULL,
  object_name => NULL,
  role_name => NULL
);"

c 'Что теперь покажет представление pg_proaudit_settings?'
s 1 'SELECT * FROM pg_proaudit_settings;'

c 'Начнем другой сеанс от имени alice:'
psql_open A 2 "'host=localhost dbname=$TOPIC_DB user=alice password=alice'"

c 'И снова проверим протокол аудита:'
sleep-ni 1
file_prot=$(sudo ls -tr $PGDATA/pg_proaudit| tail -1)
e "sudo tail -1 ${PGDATA}/pg_proaudit/${file_prot}"

p

c 'Следующая задача — включить регистрацию всех действий пользователя alice. Для этого укажем ее в соответствующем параметре функции pg_proaudit_set_rule:'
s 1 "SELECT pg_proaudit_set_rule(
  db_name => current_database(),
  event_type => 'ALL',
  object_type => NULL,
  object_name => NULL,
  role_name => 'alice'
);"

c 'Как это отобразилось в представлении pg_proaudit_settings?'
s 1 'SELECT * FROM pg_proaudit_settings;'

c 'Пользователь alice собирается создать таблицу, предоставим ей такие полномочия в схеме public:'

s 1 "GRANT CREATE ON SCHEMA public TO alice;"

c 'alice создает таблицу в своем сеансе...'

s 2 "CREATE TABLE tab1(
  id int,
  txt text
);"
sleep-ni 1

c '...и сведения об этом сразу появляются в протоколе аудита:'

file_prot=$(sudo ls -tr $PGDATA/pg_proaudit| tail -1)
e "sudo tail -4 ${PGDATA}/pg_proaudit/${file_prot}"

c 'Отменим аудит всех действий пользователя alice:'
s 1 "SELECT pg_proaudit_remove_rule(
  db_name => current_database(),
  event_type => 'ALL',
  object_type => NULL,
  object_name => NULL,
  role_name => 'alice'
);"
s 1 'SELECT * FROM pg_proaudit_settings;'

p

c 'Сфокусируем аудит на таблице tab1. Для объектов типа TABLE тип события ALL включает регистрацию команд SELECT, INSERT, UPDATE, DELETE, TRUNCATE, COPY, а также CREATE, ALTER, DROP.'
s 1 "SELECT pg_proaudit_set_rule(
  db_name => current_database(),
  event_type => 'ALL',
  object_type => 'TABLE',
  object_name => 'public.tab1',
  role_name => NULL
);"
s 1 'SELECT * FROM pg_proaudit_settings;'

c 'В сеансе пользователя alice выполним вставку в таблицу tab1 и проверим протокол аудита.'
s 2 "INSERT INTO tab1 VALUES (1984, 'Big brother is watching you...');"
s 2 "SELECT * FROM tab1;"
sleep-ni 1
file_prot=$(sudo ls -tr $PGDATA/pg_proaudit| tail -1)
e "sudo tail -2 ${PGDATA}/pg_proaudit/${file_prot}"

P 9
###############################################################################
h 'Файл pg_proaudit.conf'

c 'Функция pg_proaudit_save записывает настройки аудита в файл pg_proaudit.conf. Если не сохранить настройки, они будут потеряны при остановке сервера.'
s 1 'SELECT pg_proaudit_save();'

c 'Заглянем в файл pg_proaudit.conf:'
e "sudo cat $PGDATA/pg_proaudit.conf"

c 'А теперь сбросим все настройки аудита:'
s 1 'SELECT pg_proaudit_reset();'
c 'Никакие настройки не действуют:'
s 1 'SELECT * FROM pg_proaudit_settings;'

c 'Можно (но не очень удобно) менять файл pg_proaudit.conf любыми средствами редактирования текста. Например, удалим строку конфигурации аудита событий подключения:'
e "sudo sed -i '/authenticate/d' $PGDATA/pg_proaudit.conf"
c 'Вот что осталось в файле конфигурации:'
e "sudo cat $PGDATA/pg_proaudit.conf"

c 'А теперь считаем настройки из файла:'
s 1 'SELECT pg_proaudit_reload();'
s 1 'SELECT * FROM pg_proaudit_settings;'
c 'Настройки аудита восстановлены, за исключением протоколирования подключений.'

P 11
###############################################################################
h 'Настройка записи событий аудита'

c 'Посмотрим значения параметров конфигурации логирования по умолчанию:'
s 1 "SELECT name, setting
FROM pg_settings
WHERE name LIKE 'pg_proaudit.log_%';"

c 'Отменим запись в протокол текста команд при регистрации событий аудита:'
s 1 "ALTER SYSTEM SET pg_proaudit.log_command_text = off;"

c 'Перечитаем конфигурацию.'
s 1 "SELECT pg_reload_conf();"

c 'Удалим строки в таблице tab1 в сеансе пользователя alice:'
s 2 'DELETE FROM tab1;'

c 'Как теперь записываются события аудита? Сравните с предыдущей записью:'
sleep-ni 1
file_prot=$(sudo ls -tr $PGDATA/pg_proaudit| tail -1)
e "sudo tail -2 ${PGDATA}/pg_proaudit/${file_prot}"

###############################################################################

stop_here
cleanup
demo_end
