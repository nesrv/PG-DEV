#!/bin/bash

. ../lib
init

export HBA=`s_bare 1 "SHOW hba_file;"`

start_here
###############################################################################
h '1. Настройка аутентификации'

c 'Сохраним исходный файл настроек:'

e "sudo cp -n $HBA ~/tmp/pg_hba.conf.orig"

c 'Будем управлять аутентификацией пользователей, добавляя их в группу locals.'
c 'Запишем файл pg_hba.conf с нуля:'

e "sudo tee $HBA << EOF
local all student trust
local all +locals trust
EOF"

pgctl_reload A

c 'Создадим групповую роль:'

s 1 'CREATE ROLE locals;'

###############################################################################
h '2. Проверка'

c 'Алиса в группе locals:'

s 1 'CREATE ROLE alice LOGIN;'
s 1 'GRANT locals TO alice;'

c 'Боб пока не в группе:'

s 1 'CREATE ROLE bob LOGIN;'

e 'psql "dbname=student user=alice" -c "\conninfo"'
e 'psql "dbname=student user=bob" -c "\conninfo"'

c 'Включаем Боба в группу:'

s 1 'GRANT locals TO bob;'
e 'psql "dbname=student user=bob" -c "\conninfo"'

###############################################################################
h '2. Восстановление исходных настроек'

e "sudo cp ~/tmp/pg_hba.conf.orig $HBA"
pgctl_reload A

stop_here

###############################################################################
psql_close 1
