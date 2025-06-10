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

###############################################################################
h '2.Настройка разрешения для аутентификации клиентов по методу cert.'

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

c 'Создадим файл HBA с разрешением использовать аутентификацию cert.'
eu student "echo 'hostssl all all samehost cert' | sudo -u postgres tee ${HBA}.d/10_cert.conf"

c 'Перезагрузим сервер.'
pgctl_restart A

PSQL_PROMPT1='student=# '
psql_open A 1 -h $(hostname)
s 1 '\conninfo'

c 'Подключим расширение sslinfo'
s 1 'CREATE EXTENSION sslinfo;'
s 1 '\dx+ sslinfo'

c 'Расширение sslinfo в основном предоставляет ту же информацию, что и pg_stat_ssl, но в более удобной форме. Например:'
s 1 "SELECT ssl_client_dn() AS \"Клиент\",
ssl_issuer_dn() AS \"Центр сертификации\",
ssl_client_dn_field('CN') AS \"Уникальное имя клиента\" \gx"

p
###############################################################################
h '3.Настройка разрешения для репликации с аутентификацией по методу cert.'

c 'Добавим разрешение на выполнение репликации обладателям валидного сертификата пользователя.'
eu student "echo 'hostssl replication all samenet cert' | sudo -u postgres tee -a ${HBA}.d/10_cert.conf"
s 1 "SELECT pg_reload_conf();"
s 1 "SELECT * FROM pg_hba_file_rules WHERE database[1] = 'replication';"

p
###############################################################################
h '4.Сравнение скорости выполнения базовой резервной копии с SSL и без него.'

c 'Включим журналирование подключений.'
s 1 'ALTER SYSTEM SET log_connections TO on;'
s 1 'SELECT pg_reload_conf();'

c 'Чтобы устранить задержку на выполнение контрольной точки при самом резервном копировании, выполним ее заранее.'
s 1 'CHECKPOINT;'

c 'Создание базовой резервной копии при соединении через локальный Unix сокет. Шифрования нет.'
eu student 'time pg_basebackup -c fast -Ft -D ~/tmp/bkp'

c 'Проверим записи в журнал отчета.'
eu student 'sudo -u postgres tail /var/log/postgresql/postgresql-16-main.log'

c 'Удалим полученную копию и создадим ее заново при соединении через сетевой интерфейс с шифрованием трафика.'
eu student 'rm -rf ~/tmp/bkp'
eu student "time pg_basebackup -c fast -Ft -D ~/tmp/bkp -h $(hostname)"

c 'Снова проверим записи в журнал отчета. Должно быть видно, что использовался метод аутентификации cert.'
eu student 'sudo -u postgres tail /var/log/postgresql/postgresql-16-main.log'
c 'Не смотря на использование шифрования, значительного замедления выполнения резервного копирования нет.'

c 'Выключим журналирование подключений.'
s 1 'ALTER SYSTEM SET log_connections TO on;'
s 1 'SELECT pg_reload_conf();'

stop_here
###############################################################################

demo_end

