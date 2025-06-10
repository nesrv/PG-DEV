#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Профиль пользователя'

c 'Создадим базу данных profile:'
e "${BINPATH}createdb $TOPIC_DB"

psql_open A 1 -d $TOPIC_DB

c 'Создадим профиль с ограничением на минимальное количество отличающихся символов в пароле = 8.'
s 1 "CREATE PROFILE mgr LIMIT PASSWORD_MIN_UNIQUE_CHARS 8;"

c 'Зарегистрируем пользователя с этим профилем.'
s 1 "CREATE ROLE mgr1 LOGIN PROFILE mgr;"

c "Новое правило аутентификации для пользователя при подключении к БД $TOPIC_DB:"
e "sudo sed -i '1s/^/host $TOPIC_DB mgr1 all scram-sha-256\n/' $PGDATA_A/pg_hba.conf"
s 1 "SELECT pg_reload_conf();"

c 'Проверим профиль роли.'
s 1 "SELECT r.rolname, p.pflname, p.pflpasswordminuniqchars
FROM pg_roles r
JOIN pg_profile p
ON r.rolprofile = p.oid
WHERE r.rolname = 'mgr1';"

c 'Пароль, разрешенный профилем.'
s 1 "ALTER ROLE mgr1 PASSWORD '12345678';"
c 'Такой пароль был успешно назначен роли.'

c 'Пароль с меньшим количеством отличающихся символов.'
s 1 "ALTER ROLE mgr1 PASSWORD '12345677';"

###############################################################################

h '2. Ограничение неудачных попыток ввода пароля'

c 'Разрешим лишь две попытки.'
s 1 "ALTER PROFILE mgr LIMIT FAILED_LOGIN_ATTEMPTS 2;"

c 'Пару раз введем неверный пароль.'
e "psql 'host=localhost dbname=$TOPIC_DB user=mgr1 password=manager'"
e "psql 'host=localhost dbname=$TOPIC_DB user=mgr1 password=manager'"

c 'Блокировка должна быть уже установлена.'
s 1 "SELECT CASE rolstatus
  WHEN 0 THEN 'роль активна'
  WHEN 1 THEN 'заблокирована вручную'
  WHEN 2 THEN 'заблокирована из-за бездействия'
  WHEN 4 THEN 'заблокирована по превышению числа попыток входа'
END status
FROM pg_roles
WHERE rolname = 'mgr1';"

c 'Удалим роль:'
s 1 "DROP ROLE mgr1;"

c 'Удалим профиль:'
s 1 "DROP PROFILE mgr;"

###############################################################################

stop_here
cleanup
