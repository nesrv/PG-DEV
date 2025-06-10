#!/bin/bash

. ../lib
init

start_here 5

###############################################################################
h 'Модуль passwordcheck'

psql_open A 1

c 'Расширение passwordcheck требует загрузки одноименной разделяемой библиотеки:'
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'passwordcheck';"

c 'После подключения библиотеки необходимо перезапустить СУБД.'
pgctl_restart A
psql_open A 1

c 'Создадим базу данных и роль:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "CREATE ROLE bob LOGIN;"

c "Добавим в начало pg_hba.conf правило аутентификации для нового пользователя при подключении к БД $TOPIC_DB:"

e "sudo sed -i '1s/^/host $TOPIC_DB bob all scram-sha-256\n/' $PGDATA_A/pg_hba.conf"

s 1 "SELECT pg_reload_conf();"

c 'Проверим, можно ли установить пользователю нестойкий пароль bob123:'
s 1 "ALTER ROLE bob PASSWORD 'bob123';";

c 'Теперь попробуем установить сложный пароль:'
s 1 "ALTER ROLE bob PASSWORD 'GGU2015ujlf';";

c 'Удалим модуль passwordcheck и снова перезапустим СУБД.'
s 1 "ALTER SYSTEM RESET shared_preload_libraries;"
pgctl_restart A

P 11
###############################################################################
h 'Профили пользователей'

psql_open A 1 -d $TOPIC_DB

c 'Пока ничего не мешает пользователю установить простой пароль:'
s 1 "ALTER ROLE bob PASSWORD 'bob';"

c 'Создадим профиль:'
s 1 "CREATE PROFILE IF NOT EXISTS prof LIMIT
  PASSWORD_LIFE_TIME 60
  PASSWORD_GRACE_TIME 7
  PASSWORD_MIN_LEN 8
  PASSWORD_REQUIRE_COMPLEX;"
c 'Имя профиля prof, пароль необходимо менять через 60 дней. Еще в течение 7 дней будут выводиться предупреждения о необходимости поменять пароль.'
c 'Минимальная длина пароля — 8 символов, причем пароль должен содержать как буквы, так и другие символы, а имя пользователя не должно входить в пароль.'

c 'Назначим роли bob профиль prof:'
s 1 "ALTER ROLE bob PROFILE prof;"

c 'Как убедиться, что с ролью связан профиль, не являющийся профилем по умолчанию?'
s 1 "SELECT r.rolname, p.pflname 
FROM pg_authid r
  JOIN pg_profile p ON p.oid = r.rolprofile 
WHERE r.rolname = 'bob';"

c 'Попробуем установить короткий пароль:'
s 1 "ALTER ROLE bob PASSWORD 'bob123';"

c 'Попробуем сделать пароль длиннее:'
s 1 "ALTER ROLE bob PASSWORD 'bob12345';"

c 'Усложним:'
s 1 "ALTER ROLE bob PASSWORD 'GGU2015ujlf';"

c 'Модифицируем профиль prof, установив ограничение в три неудачные попытки начать сеанс до блокировки учетной записи.'
s 1 "ALTER PROFILE prof LIMIT FAILED_LOGIN_ATTEMPTS 3;"

c 'Боб пытается подключиться три раза с неправильными паролями:'

e "psql 'host=localhost dbname=$TOPIC_DB user=bob password=12345678'"
e "psql 'host=localhost dbname=$TOPIC_DB user=bob password=qwerty'"
e "psql 'host=localhost dbname=$TOPIC_DB user=bob password=q1w2e3r4'"

c 'Теперь роль заблокирована:'

s 1 "SELECT CASE rolstatus
  WHEN 0 THEN 'роль активна'
  WHEN 1 THEN 'заблокирована вручную'
  WHEN 2 THEN 'заблокирована из-за бездействия'
  WHEN 4 THEN 'заблокирована по превышению числа попыток входа'
END status
FROM pg_roles
WHERE rolname = 'bob';"

c 'Разблокируем роль, дадим Бобу шанс вспомнить пароль:'

s 1 "ALTER ROLE bob ACCOUNT UNLOCK;"
e "psql 'host=localhost dbname=$TOPIC_DB user=bob password=GGU2015ujlf' -c '\conninfo'"

p

c 'Следующим образом можно установить профиль по умолчанию:'
s 1 "ALTER ROLE bob PROFILE default;"

c 'Удалим профиль:'
s 1 "DROP PROFILE prof;"

c 'Удалим роль:'
s 1 "DROP ROLE bob;"

###############################################################################

stop_here
cleanup
demo_end
