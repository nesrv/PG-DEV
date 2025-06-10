#!/bin/bash


. ../lib
init

export HBA=`s_bare 1 "SHOW hba_file;"`

start_here 5
###############################################################################

h '1.Генерация клиентского сертификата'

c 'Создадим каталог для клиентских сертификатов. Пока в нем потребуется лишь сертификат центра сертификации.'
rm -rf ~student/.postgresql
eu student 'mkdir ~student/tmp/.postgresql'
eu student 'ln -s ~student/tmp/.postgresql ~student'
eu student 'cp /etc/pgssl/root/root.crt ~student/.postgresql'
eu student 'ls ~student/.postgresql/'

c 'Запрос на сертификацию.'
eu student "openssl req -new -nodes -text -out ~/.postgresql/postgresql.csr -keyout ~/.postgresql/postgresql.key -subj '/CN=student'"

c 'Сертификат клиента.'
eu student "sudo openssl x509 -req -text -days 3650 -CA ~/.postgresql/root.crt -CAkey /etc/pgssl/root/root.key -CAcreateserial -in ~/.postgresql/postgresql.csr -out ~/.postgresql/postgresql.crt"

c 'Владельцем сертификата должен являться student.'
eu student 'sudo chown student:student ~/.postgresql/postgresql.crt'
eu student 'ls -l ~/.postgresql/'

c 'Клиентский сертификат готов.'
p

c 'Запишем в каталог /etc/postgresql/16/main/conf.d параметры конфигурации сервера для SSL. Настроим сервер для прослушивания всех интерфейсов.'
eu student "cat << EOT | sudo -u postgres tee /etc/postgresql/16/main/conf.d/ssl.conf
listen_addresses = '*'
ssl_ca_file   = '/etc/pgssl/root/root.crt'
ssl_cert_file = '/etc/pgssl/serv/serv.crt'
ssl_key_file  = '/etc/pgssl/serv/serv.key'
EOT"

local1st=$(psql -At -c "select min(line_number) from pg_hba_file_rules where type = 'local'")
sudo -u postgres sed -i.bak "${local1st}a\#\n# Каталог для дополнительной конфигурации HBA\ninclude_dir ${HBA}.d\n" ${HBA}

c 'Создадим каталог.'
eu student "sudo -u postgres mkdir ${HBA}.d"

c 'Текстовым редактором изменим pg_hba.conf следующим образом:'
eu student "sudo -u postgres sed -n '${local1st},\$p' ${HBA}"

c 'Перезагрузим сервер.'
pgctl_restart A

p
###############################################################################
h '2. Регистрация роли.'

PSQL_PROMPT1='student=# '
psql_open A 1

s 1 "CREATE USER user1 PASSWORD 'SECRET';"
c 'В сертификате CN=student, но намеренно зарегистрирована роль user1.'

p
###############################################################################
h '3. Проверка шифрования трафика.'

c 'Создадим файл HBA с разрешением user1 подключаться к базе данных student при успешной аутентификации методом password. SSL выключен.'
eu student "echo 'hostnossl student user1 samehost password' | sudo -u postgres tee ${HBA}.d/10_user1.conf"

c 'Перечитаем конфигурацию.'
s 1 'SELECT pg_reload_conf();'

c 'Запустим перехват трафика, направленного на порт TCP 5432, на всех сетевых интерфейсах.'
eu student 'sudo tcpdump -w ~/tmp/tcpdump.bin -i any "dst port 5432" >& ~/tmp/tcpdump.log &'

c 'Выполним код SQL в сессии user1, используя аутентификацию password при отсутствии шифрования.'
eu student "psql \"host=$(hostname) dbname=student user=user1 password=SECRET sslmode=disable\" -c 'SELECT version()'"

c 'Завершим перехват трафика.'
eu student 'sudo killall tcpdump'

c 'Проверим, видно ли в трафике имена пользователей, пароли и выполненные команды.'
eu student 'sudo chown student:student ~/tmp/tcpdump.bin'
eu student "tcpdump -Aqr ~/tmp/tcpdump.bin 2> /dev/null | egrep -i '(user1|select|secret)'"
c 'В перехваченном трафике видны незашифрованные имя пользователя, пароль и выполненная команда.'

p

c 'Изменим разрешения на подключение user1, оставив аутентификацию password, но включив SSL и потребовав проверить, действительно ли клиентский сертификат подписан центром сертификации, которому доверяет сервер.'
eu student "echo 'hostssl student user1 samehost password clientcert=verify-ca' | sudo -u postgres tee ${HBA}.d/10_user1.conf"

c 'Перечитаем конфигурацию и повторим эксперимент.'
s 1 'SELECT pg_reload_conf();'

c 'Удалим результаты предыдущего перехвата и запустим перехват снова.'
eu student 'sudo rm -f ~/tmp/tcpdump.{bin,log}' 
eu student 'sudo tcpdump -w ~/tmp/tcpdump.bin -i any "dst port 5432" >& ~/tmp/tcpdump.log &'

c 'Выполним код SQL в сессии user1, используя аутентификацию password с включенным шифрованием и проверкой клиентского сертификата.'
eu student "psql \"host=$(hostname) dbname=student user=user1 password=SECRET sslmode=require\" -c 'SELECT version()'"

c 'Завершим перехват трафика.'
eu student 'sudo killall tcpdump'

c 'Проверим, видно ли в трафике имена пользователей, пароли и выполненные команды.'
eu student 'sudo chown student:student ~/tmp/tcpdump.bin'
eu student "tcpdump -Aqr ~/tmp/tcpdump.bin 2> /dev/null | egrep -i '(user1|select|secret)'"
c 'В выводе есть строки, но они отфильтрованы egrep и ни пароля, ни команд среди них нет - трафик зашифрован.'

p

c 'Теперь в HBA файле запретим шифрование и используем метод аутентификации scram-sha-256.'
eu student "echo 'hostnossl student user1 samehost scram-sha-256' | sudo -u postgres tee ${HBA}.d/10_user1.conf"

c 'Перечитаем конфигурацию.'
s 1 'SELECT pg_reload_conf();'

c 'Запустим перехват трафика.'
eu student 'sudo rm -f ~/tmp/tcpdump.{bin,log}' 
eu student 'sudo tcpdump -w ~/tmp/tcpdump.bin -i any "dst port 5432" >& ~/tmp/tcpdump.log &'

c 'Выполним код SQL в сессии user1, используя аутентификацию scram-sha-256 при отсутствии шифрования.'
eu student "psql \"host=$(hostname) dbname=student user=user1 password=SECRET sslmode=disable\" -c 'SELECT version()'"

c 'Завершим перехват трафика.'
eu student 'sudo killall tcpdump'

c 'Проверим, видно ли в трафике имена пользователей, пароли и выполненные команды.'
eu student 'sudo chown student:student ~/tmp/tcpdump.bin'
eu student "tcpdump -Aqr ~/tmp/tcpdump.bin 2> /dev/null | egrep -i '(user1|select|secret)'"
c 'В перехвате видны имя пользователя и выполненные команды.'

p

c 'Теперь в HBA файле потребуем шифровать трафик. Клиентский сертификат не используется.'
eu student "echo 'hostssl student user1 samehost scram-sha-256' | sudo -u postgres tee ${HBA}.d/10_user1.conf"

c 'Перечитаем конфигурацию.'
s 1 'SELECT pg_reload_conf();'

c 'Запустим перехват трафика.'
eu student 'sudo rm -f ~/tmp/tcpdump.{bin,log}' 
eu student 'sudo tcpdump -w ~/tmp/tcpdump.bin -i any "dst port 5432" >& ~/tmp/tcpdump.log &'

c 'Выполним код SQL в сессии user1 с шифрованием.'
eu student "psql \"host=$(hostname) dbname=student user=user1 password=SECRET sslmode=require\" -c 'SELECT version()'"

c 'Завершим перехват трафика.'
eu student 'sudo killall tcpdump'

c 'Проверим, видно ли в трафике имена пользователей, пароли и выполненные команды.'
eu student 'sudo chown student:student ~/tmp/tcpdump.bin'
eu student "tcpdump -Aqr ~/tmp/tcpdump.bin 2> /dev/null | egrep -i '(user1|select|secret)'"
c 'Снова в перехвате нет ни пароля, ни команд среди них нет так как трафик зашифрован.'

stop_here
###############################################################################

demo_end

