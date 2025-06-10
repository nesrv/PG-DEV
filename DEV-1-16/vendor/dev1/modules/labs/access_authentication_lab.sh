#!/bin/bash

. ../lib
init

export HBA=`s_bare 1 "SHOW hba_file;"`

start_here

###############################################################################
h '1. Настройка аутентификации'

c 'Сохраним исходный файл настроек:'

e "sudo cp -n $HBA ~/tmp/pg_hba.conf.orig"

c 'Теперь перезапишем pg_hba.conf с нуля:'

e "sudo tee $HBA << EOF
local  all  postgres       trust
local  all  student        trust
host   all  all       all  md5
EOF"

pgctl_reload A

###############################################################################
h '2. Создание ролей'

s 1 "SHOW password_encryption;"
s 1 "CREATE ROLE alice LOGIN PASSWORD 'alice';"

s 1 "SET password_encryption='scram-sha-256';"
s 1 "CREATE ROLE bob LOGIN PASSWORD 'bob';"

###############################################################################
h '3. Проверка подключения'

c 'Поскольку настройки требуют ввода пароля, мы укажем его явно в строке подключения.'
c 'При выполнении этого задания лучше ввести пароль вручную, чтобы убедиться в том, что он запрашивается.'

s 1 '\c "dbname=student user=alice host=localhost password=alice"'

s 1 '\c "dbname=student user=bob host=localhost password=bob"'

###############################################################################
h '4. Просмотр паролей'

psql_close 1
psql_open A 1

s 1 "SELECT rolname, rolpassword FROM pg_authid WHERE rolname IN ('alice','bob') \gx"

c 'Пароли хранятся как значение хеш-функции, не допускающее расшифровки. Сервер всегда сравнивает между собой зашифрованные значения — введенный пароль и значение из pg_authid.'

###############################################################################
h '5. Восстановление исходных настроек'

e "sudo cp ~/tmp/pg_hba.conf.orig $HBA"

pgctl_reload A

stop_here

s 1 'DROP ROLE alice;'
s 1 'DROP ROLE bob;'

psql_close 1
