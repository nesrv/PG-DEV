#!/bin/bash


. ../lib
init

export HBA=`s_bare 1 "SHOW hba_file;"`

start_here

###############################################################################
h '1. Фиксация подключений в журнале отчета.'

c 'Запись в журнал отчета о подключениях.'
s 1 "ALTER SYSTEM SET log_connections TO on;"

p
###############################################################################
h '2. Регистрация пользователя.'

c 'Создадим в PostgreSQL роль pamuser и зарегистрируем одноименного пользователя операционной системы.'
s 1 'CREATE ROLE pamuser LOGIN;'
eu student 'id pamuser 2> /dev/null || sudo useradd pamuser'
c 'Команда useradd создает учетную запись пользователя pamuser. Если учетная запись существует, команда useradd не вызывается.'

c 'Установим пароль пользователю pamuser, совпадающий с его именем.'
echo 'pamuser:pamuser' | sudo chpasswd
c 'Команда chpasswd установила пользователю операцинной системы pamuser пароль, приняв из stdin пару <пользователь>:<пароль>'

p
###############################################################################
h '3. Настройка HBA'

# Вставим настройку для pamuser перед первой директивой local в pg_hba.conf
local1st=$(psql -At -c "select min(line_number) from pg_hba_file_rules where type = 'local'")
sudo -u postgres sed -i.bak "${local1st}i\local all pamuser pam pamservice=login\n" ${HBA}

c 'Отредактируем pg_hba.conf следующим образом (только необходимые здесь директивы):'
eu student "sudo -u postgres sed -n '${local1st},\$p' ${HBA}"

s 1 "SELECT * FROM pg_hba_file_rules WHERE 'pamuser' = ANY(user_name) \gx"
s 1 "SELECT pg_reload_conf();"

p
###############################################################################
h '4. Права доступа для пользователя ОС postgres.'

c 'Проверим права доступа на /etc/shadow'
eu student 'ls -l /etc/shadow'

c 'Пользователи операционной системы, входящие в группу shadow, могут читать файл. В этом файле находятся шифрованные пароли, возможность их чтения необходима PostgreSQL для локальной аутентификации PAM. Добавим пользователя операционной системы postgres в группу shadow. Это позволит процессам экземпляра читать шифрованные пароли.'
eu student 'sudo gpasswd -a postgres shadow'
eu student 'id postgres'

p
###############################################################################
h '5. Перезапуск СУБД и подключение.'

c 'Рестартуем экземпляр.'
psql_close 1
pgctl_restart A
PSQL_PROMPT1='student=# '
psql_open A 1 student


c 'Проверим, сможет ли pamuser подключиться...'
eu student 'psql "user=pamuser password=pamuser dbname=student" -c "\conninfo"'
eu student 'tail -3 /var/log/postgresql/postgresql-16-main.log'

c 'Пользователь pamuser более не нужен, удалим его и выведем пользователя postgres из группы shadow.'
eu student 'sudo gpasswd -d postgres shadow'
eu student 'sudo userdel pamuser'

c 'Удалим из pg_hba.conf разрешение для pamuser.'
eu student "sudo -u postgres sed -i '/pamuser/d' ${HBA}"

stop_here
###############################################################################

demo_end
