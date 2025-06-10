#!/bin/bash


. ../lib
init

export HBA=`s_bare 1 "SHOW hba_file;"`

start_here 5
###############################################################################

h 'Настройка сервера на использование сертификатов.'

c 'Конфигурация PostgreSQL в XUbuntu по умолчанию.'
s 1 '\dconfig ssl_[ck][ae]*file'

c 'Проверим указанный в конфигурации сертификат.'
s 1 '\! openssl x509 -noout -text -in /etc/ssl/certs/ssl-cert-snakeoil.pem -certopt no_sigdump,no_pubkey'
c 'Сертификат самоподписанный и не предназначенный для центра сертификации.'
p

c 'Для курса предварительно созданы:'
ul '/etc/pgssl/root/root.crt - корневой сертификат центра сертификации;'
ul '/etc/pgssl/serv/serv.crt - сертификат сервера PostgreSQL;'
ul '/etc/pgssl/serv/serv.key - закрытый ключ сервера PostgreSQL.'

c 'Исследуем предварительно созданный сертификат serv.crt'
s 1 '\! openssl x509 -noout -text -in /etc/pgssl/serv/serv.crt -certopt no_sigdump,no_pubkey'

c 'Обратите внимание на следующие моменты в сертификате serv.crt:'
ul 'Issuer: ... CN = PPG_EDU_CA - Common Name выпустившего сертификат сервера центра сертификации;'
ul 'Subject: ... CN = ppgedu.local - FQDN имя узла, где запущен сервер PostgreSQL;'
ul 'Расширенный атрибут X509v3 Subject Alternative Name DNS также должен соответствовать FQDN сервера;'
ul 'Расширенный атрибут X509v3 Subject Alternative Name IP должен соответствовать IPv4 адресу на сетевом интерфейсе сервера.'
p

c 'Воспользуемся каталогом /etc/postgresql/16/main/conf.d для добавления параметров конфигурации сервера. Сервер должен прослушивать все интерфейсы.'
eu student "cat << EOT | sudo -u postgres tee /etc/postgresql/16/main/conf.d/ssl.conf
listen_addresses = '*'
ssl_ca_file   = '/etc/pgssl/root/root.crt'
ssl_cert_file = '/etc/pgssl/serv/serv.crt'
ssl_key_file  = '/etc/pgssl/serv/serv.key'
EOT"

c 'Проверим и применим конфигурацию SSL.'
s 1 "SELECT * FROM pg_file_settings WHERE name ~ 'ssl';"
s 1 "SELECT pg_reload_conf();"
s 1 "\c 'host=localhost password=student'"
s 1 "\conninfo"
c 'Обратите внимание, что пока никакой проверки сертификатов не осуществляется, но трафик уже шифруется.'
p

c 'Теперь добавим разрешение подключаться посредством основного сетевого интерфейса - необходимо внести изменения в pg_hba.conf'
c 'Для удобства добавим директиву подключения дополнительных файлов в pg_hba.conf'
c 'Существуют следующие директивы:'
ul 'include - подключить содержимое дополнительного файла;'
ul 'include_if_exists - подключить содержимое дополнительного файла при его наличии;'
ul 'include_dir - подключить файлы в заданном каталоге, завершающиеся на .conf'

c 'Создадим каталог для дополнительных файлов настройки аутентификации и включим его в pg_hba.conf'
eu student "sudo -u postgres mkdir ${HBA}.d"

# Вставим include_dir после первой директивы в pg_hba.conf
local1st=$(psql -At -c "select min(line_number) from pg_hba_file_rules where type = 'local'")
sudo -u postgres sed -i.bak "${local1st}a\#\n# Каталог для дополнительной конфигурации HBA\ninclude_dir ${HBA}.d\n" ${HBA}

c 'Отредактируем pg_hba.conf следующим образом (только необходимые здесь директивы):'
eu student "sudo -u postgres sed -n '${local1st},\$p' ${HBA}"
p

c 'Отредактируем дополнительный файл HBA так, чтобы разрешить подключение посредством основного сетевого интерфейса.'
echo 'host all all samehost scram-sha-256' | sudo -u postgres tee ${HBA}.d/10_host_scram.conf > /dev/null
eu student "cat ${HBA}.d/10_host_scram.conf"

c 'Перезагрузим сервер, поскольку был изменен параметр listen_addresses.'
pgctl_restart A
PSQL_PROMPT1='student=# '
psql_open A 1
s 1 "SELECT * FROM pg_hba_file_rules WHERE address = 'samehost' \gx"

P 8
###############################################################################
h 'Клиентский параметр соединения sslmode'

c 'Откроем новый сеанс без защиты шифрованием. Для этого в URI соединения укажем параметр sslmode=disable'
psql_open A 2 "'postgresql://student@$(hostname):5432/student?password=student&sslmode=disable'"
PSQL_PROMPT2='student=# '

c 'Представление pg_stat_ssl информирует от состоянии сессий в аспекте SSL.'
s 2 "SELECT * FROM pg_stat_ssl
	WHERE pid = pg_backend_pid() \gx"
c 'В поле ssl видно значение false - нет шифрования.'
p

c 'Включим шифрование без старта новой сессии. Достаточно установить параметр соединения sslmode=prefer'
s 2 '\c -reuse-previous=on sslmode=prefer'
s 2 "SELECT * FROM pg_stat_ssl
	WHERE pid = pg_backend_pid() \gx"
c 'Теперь трафик этой сессии шифруется. Поле cipher информирует о протоколе шифрования.'
psql_close 2

P 10
###############################################################################
h 'Проверка сертификатов центра сертификации и сервера'

c 'Создадим каталог для клиентских сертификатов. Пока в нем потребуется лишь сертификат центра сертификации.'
rm -rf ~student/.postgresql
eu student 'mkdir ~student/tmp/.postgresql'
eu student 'ln -s ~student/tmp/.postgresql ~student'
eu student 'cp /etc/pgssl/root/root.crt ~student/.postgresql'
eu student 'ls ~student/.postgresql/'

c 'Подключимся во второй сесии в режиме проверки сертификата центра сертификации.'
eu student "psql -c '\conninfo' 'host=localhost password=student sslmode=verify-ca'"
c 'В этом режиме клиент проверяет лишь достоверность сертификата центра сертификации, которым подписан сертификат сервера. Обратите внимание, что соединение было произведено через закольцовывающий интерфейс loopback, которому соответствует имя localhost. В сертификате сервера, конечно, это имя хоста не указано.'
p

c 'Попробуем повторить эксперимент, указав параметр sslmode, требующий проверить имя сервера в его сертификате.'
eu student "psql -c '\conninfo' 'host=localhost password=student sslmode=verify-full'"
c 'Поскольку в сертификате указано другое имя хоста, соединение не разрешено.'
p

c 'В режиме sslmode=verify-full требуется совпадение имени хоста сервера с тем, что указано в сертификате, помимо также выполняемой проверки валидности сертификата центра сертификации.'
eu student "psql -c '\conninfo' 'host=$(hostname) password=student sslmode=verify-full'"

c 'В режиме verify-full выполняются следующие проверки:'
ul 'имя хоста сервера сверяется с атрибутом сертификата Subject Alternative Name - SAN;'
ul 'в случае его отсутствия имя хоста проверяется по атрибуту сертификата Common Name - CN.'
p

c 'Теперь попробуем подключиться в том же режиме verify-ful, использовав IPv4 адрес, а не имя сервера.'
eu student "psql -c '\conninfo' 'host=$(hostname -I) password=student sslmode=verify-full'"
c 'В сертификате имеется соответствующий расширенный атрибут. При его отсутствии также будет обращение к атрибуту CN.'

P 12
###############################################################################
h 'Клиентские сертификаты'

c 'В предыдущих примерах клиент проверял сертификат сервера. Теперь поставим иную задачу: для установки соединения требуется наличие действительного сертификата клиента. Сервер может потребовать сертификат клиента двумя способами:'
ul 'указать в pg_hba.conf тип подключения hostssl, задать требуемый способ аутентификации и добавить после него параметр clientcert, назначив ему либо verify-ca для проверки подписи центра сертификации в клиентском сертификате, либо verify-full, добавляющий к этому требование совпадения имени клиента с атрибутом CN в клиентском сертификате;'
ul 'применить метод аутентификации cert.'
p

c 'Опробуем способ с параметром clientcert и методом аутентификации scram-sha-256. В этом случае для успешного соединения требуется наличие действительного сертификата клиента и ввод правильного пароля, как при использовании простого scram-sha-256.'
c 'Сгенерировать сертификат клиента можно несколькими способами. Воспользуемся двухшаговым подходом: создадим запрос на сертификацию клиента и подпишем его в имеющемся центре сертификации, выпустив таким образом сертификат клиента.'
eu student "openssl req -new -nodes -text -out ~/.postgresql/postgresql.csr -keyout ~/.postgresql/postgresql.key -subj '/CN=student'"
c 'Режим req команды openssl использован здесь для создания запроса на сертификацию (Certification Signing Request - CSR). Это новый запрос - параметр -new. Сгенерированный закрытый ключ, заданный параметром -keyout, не защищен парольной фразой и не зашифрован - параметр -nodes. Запись в CSR произведена текстом - -text. Результирующий CSR помещен в файл, заданный параметром -out. Атрибут CN задает имя субъекта, подлежащего проверке.'
p

c 'Полученный в результате CSR следует подписать в том же центре сертификации, которому доверяет сервер. Сертификат этого центра уже находится в каталоге ~/.postgresql. Сгенерируем сертификат клиента.'
eu student "sudo openssl x509 -req -text -days 3650 -CA ~/.postgresql/root.crt -CAkey /etc/pgssl/root/root.key -CAcreateserial -in ~/.postgresql/postgresql.csr -out ~/.postgresql/postgresql.crt"
c 'Команда openssl в режиме x509, подписывающая CSR и выпускающая сертификат, должна иметь доступ к закрытому ключу центра сертификации. Поэтому ее приходится запускать посредством sudo. Параметр -days задает срок, в течении которого сертификат действителен. Параметр -CA задает путь к сертификату центра сертификации. Параметр -CAkey указывает местоположение закрытого ключа центра сертификации. Параметр -CAcreateserial необходим для создания нумератора клиенских сертификатов (сочетание серийного номера сертификата с выдавшим его центром сертификации гарантирует однозначную идентификацию сертификата).'
p

c 'Владельцем сертификата должен являться действующий субъект. В нашем случае - student.'
eu student 'sudo chown student:student ~/.postgresql/postgresql.crt'
eu student 'ls -lL ~/.postgresql/'
p

c 'Клиентский сертификат готов. Изменим запись HBA так, чтобы сервер выполнял полную проверку клиентского сертификата вместе с аутентификацией scram-sha-256.'
c 'Отредактируем дополнительный файл HBA следующим образом:'
sudo -u postgres sed -i -e 's/host/hostssl/' -e 's/$/ clientcert=verify-full/' ${HBA}.d/10_host_scram.conf
eu student "sudo -u postgres cat ${HBA}.d/10_host_scram.conf"
s 1 "SELECT pg_reload_conf();"
s 1 "SELECT * FROM pg_hba_file_rules WHERE type = 'hostssl' \gx"

c 'Откроем второй сеанс от имени student.'
PSQL_PROMPT2='student=# '
psql_open A 2
s 2 "\c 'user=student host=$(hostname) password=student'"
s 2 "SELECT * FROM pg_stat_ssl
	WHERE pid = pg_backend_pid() \gx"
c 'Обратите внимание на то, что клиентский сертификат предоставлен, виден атрибут CN, серийный номер клиентского сертификата и подписавший его центр сертификации.'

psql_close 2

P 14
###############################################################################
h 'Аутентификация по клиентскому сертификату'

c 'Тип аутентификации cert позволяет аутентифицировать клиента по его сертификату. Изменим конфигурацию HBA следующим образом:'
sudo -u postgres sed -i -e 's/scram-sha-256.*$/cert/' ${HBA}.d/10_host_scram.conf
eu student "sudo -u postgres cat ${HBA}.d/10_host_scram.conf"
s 1 "SELECT pg_reload_conf();"
s 1 "SELECT * FROM pg_hba_file_rules WHERE type = 'hostssl' \gx"
c 'Задавать явно какие-либо значения для параметра clientcert при использовании метода аутентификации cert не требуется. Они задаются автоматически в режиме verify-full'

c 'Снова откроем второй сеанс.'
PSQL_PROMPT2='student=# '
psql_open A 2
c 'Поскольку сертификат клиента не защищен шифрованием, парольную фразу для использования сертификата вводить не придется. Обычный пароль, хранимый в СУБД также не используется, поэтому уберем его из строки соединения.'
s 2 "\c 'user=student host=$(hostname)'"
s 2 "SELECT * FROM pg_stat_ssl
	WHERE pid = pg_backend_pid() \gx"

stop_here
###############################################################################

demo_end

