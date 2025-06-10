#!/bin/bash

. ../lib

init

start_here


###############################################################################
h '1. Добавление ролей'

c 'Зарегистрируем роли с правом входа в сеанс.'
s 1 'CREATE ROLE alice LOGIN;'
s 1 'CREATE ROLE bob LOGIN;'

###############################################################################
h '2. Ограничение использования trust'

c 'Отредактируем содержимое pg_hba.conf, разрешив метод trust лишь для postgres и student.'
e "sudo sed -i 's/^local.*all.*all.*trust.*$/local all postgres,student trust\n/' /etc/postgresql/16/main/pg_hba.conf"

c 'Вот что получилось:'
s 1 "SELECT type,database,user_name,address,auth_method,error
FROM pg_hba_file_rules
ORDER BY rule_number;"

c 'Применим конфигурацию.'
s 1 'SELECT pg_reload_conf();'

c 'Теперь alice и bob не могут подключиться:'
e 'psql -l -U alice'
e 'psql -l -U bob'

p

###############################################################################
h '3. Метод аутентификации peer'

c 'Используя текстовый редактор, добавим еще одну строку с методом аутентификации peer, чтобы разрешить подключение пользователям alice и bob.'
e "sudo sed -i '/^local.*all.*postgres,student.*$/alocal all alice,bob peer' /etc/postgresql/16/main/pg_hba.conf"

c 'Содержимое pg_hba.conf:'
s 1 "SELECT type,database,user_name,address,auth_method,error
FROM pg_hba_file_rules
ORDER BY rule_number;"

c 'Перечитаем конфигурацию.'
s 1 'SELECT pg_reload_conf();'

c 'Однако по-прежнему эти учетные записи не могут войти в сеанс, хотя сообщение об ошибке изменилось.'
e 'psql -l -U alice'
e 'psql -l -U bob'

c 'Метод peer требует совпадения учетной записи в ОС с именем роли в PostgreSQL. Создадим отображение роли alice на пользователя ОС student, добавив строку в файл pg_ident.conf. Для роли bob отображение задавать не будем.'
e "echo 'stmap student alice' | sudo tee -a /etc/postgresql/16/main/pg_ident.conf"

c 'И допишем в добавленную строку параметр map, задающий имя отображения.'
e "sudo sed -i 's/peer.*$/peer map=stmap/' /etc/postgresql/16/main/pg_hba.conf"

c 'Содержимое pg_hba.conf:'
s 1 "SELECT type,database,user_name,address,auth_method,options,error
FROM pg_hba_file_rules
ORDER BY rule_number;"

c 'Перечитаем конфигурацию.'
s 1 'SELECT pg_reload_conf();'

c 'Теперь alice может подключиться к базе данных и выполнить команды.'
e "psql -c '\conninfo' -U alice -d student"

c 'А bob — нет.'
e "psql -c '\conninfo' -U bob -d student"

###############################################################################
h '4. Одно отображение для нескольких ролей'

c 'Разрешим пользователю bob входить в сеанс на таких же условиях, как alice.'
e "echo 'stmap student bob' | sudo tee -a /etc/postgresql/16/main/pg_ident.conf"
 
c 'Добавленные строки в pg_ident.conf:'
e "sudo tail -n2 /etc/postgresql/16/main/pg_ident.conf"

c 'Перечитаем конфигурацию.'
s 1 'SELECT pg_reload_conf();'

c 'Теперь и alice, и bob смогут подключиться.'
e "psql -c '\conninfo' -U alice -d student"
e "psql -c '\conninfo' -U bob -d student"

###############################################################################
stop_here
cleanup
demo_end
