#!/bin/bash


. ../lib
init
kdestroy

export HBA=`s_bare 1 "SHOW hba_file;"`
local1st=$(psql -At -c "select min(line_number) from pg_hba_file_rules where type = 'local'")

start_here 6
###############################################################################
h 'Простое связывание LDAP'

c 'Подготовим PostgreSQL на прослушивание всех сетевых интерфейсов и запись в журнал отчета о подключениях.'
s 1 "ALTER SYSTEM SET listen_addresses = '*';"
s 1 "ALTER SYSTEM SET log_connections TO on;"

psql_close 1
pgctl_restart A
PSQL_PROMPT1='student=# '
psql_open A 1 student

c 'Создадим каталог для дополнительных файлов настройки аутентификации и включим его в pg_hba.conf'
eu student "sudo -u postgres mkdir ${HBA}.d"

c 'Вставим include_dir после первой директивы в pg_hba.conf'
eu student "sudo -u postgres sed -i.bak \"${local1st}a\#\n# Каталог для дополнительной конфигурации HBA\ninclude_dir ${HBA}.d\n\" ${HBA}"

c 'Результат редактирования pg_hba.conf'
eu student "sudo -u postgres sed -n '${local1st},\$p' ${HBA}"
p

c 'Проверяя аутентичность роли PostgreSQL может обращаться к дереву LDAP:'
ul 'В незащищенной сессии, независимо от SSL защиты подключения клиента к PostgreSQL.'
ul 'В защищенной SSL/TLS сессии, обращаясь на 636 порт TCP - ldaps.'
ul 'В защищенной SSL/TLS сессии, после инициализации StartTLS на порт 389 - ldap.'

c 'Вставим правило, разрешающее для Алисы аутентификацию в LDAP без защиты SSL/TLS обращения PostgreSQL к LDAP методом простого подключения.'
eu student "echo 'host all alice samehost ldap ldapserver=127.0.0.1 ldapprefix=\"cn=\" ldapsuffix=\", dc=dbs, dc=local\"' | sudo -u postgres tee ${HBA}.d/pg_hba_ext.conf"

c 'Проверим и перечитаем конфигурацию.'
s 1 "SELECT * FROM pg_hba_file_rules WHERE address = 'samehost' \gx"
s 1 "SELECT pg_reload_conf();"

c 'При внешней аутентификации в LDAP роль должна быть зарегистрирована в PostgreSQL, но пароль хранится в дереве LDAP.'
s 1 "CREATE ROLE alice LOGIN;"

c 'Учетные записи пользователей уже заведены в дереве LDAP.'
eu student 'ldapsearch -x -LLL -H ldaps://$(hostname) -b dc=dbs,dc=local -D cn=admin,dc=dbs,dc=local -w admin "(|(cn=alice)(cn=bob))" cn'
c 'Утилита ldapsearch выполняет поиск в дереве LDAP, подключившись к ветви, указанной ключом -b. Ключ -x используется для простого соединения без механизмов шифрования SASL. Ключ -D указывает от имени кого выполняется запрос, а -w задает в командной строке его пароль. Конструкция в круглых скобках задает фильтрующий предикат с помощью логического выражения ИЛИ. Завершает командную строку cn - имя атрибута найденных сущностей, который необходимо получить. Ключи -LLL понижают информативность вывода.'

c 'Выполним команду от имени Алисы и проверим журнал отчета. Подключение PostgreSQL к LDAP без SSL/TLS.'
eu student 'psql "host=localhost user=alice password=alice dbname=student" -c "\conninfo"'
eu student 'tail -3 /var/log/postgresql/postgresql-16-main.log'

p

c 'На примере Боба проверим аутентификацию с защитой обращения PostgreSQL к LDAP с помощью SSL.'
s 1 "CREATE ROLE bob LOGIN;"

c 'Перепишем дополнительный файл конфигурации HBA, разрешив Бобу аутентификацию по методу простого связывания с LDAP, с защитой обращения PostgreSQL к LDAP посредством SSL. Удобно воспользоваться форматом RFC4516 вместо указания опций подключения.'
eu student "echo 'host all bob samehost ldap ldapurl=\"ldaps://dbs.local/dc=dbs,dc=local?cn?sub\"' | sudo -u postgres tee ${HBA}.d/pg_hba_ext.conf"

c 'Проверим и перечитаем конфигурацию.'
s 1 "SELECT * FROM pg_hba_file_rules WHERE address = 'samehost' \gx"
s 1 "SELECT pg_reload_conf();"

c 'Проверим, подключится ли Боб.'
eu student 'psql "host=localhost user=bob password=bob dbname=student" -c "\conninfo"'
eu student 'tail -3 /var/log/postgresql/postgresql-16-main.log'

P 8
###############################################################################
h 'Поиск в LDAP +связывание'

c 'Испытаем поиск+связывание на Чарли'
s 1 "CREATE ROLE charlie LOGIN;"

c 'Его учетная запись зарегистрирована в LDAP поддереве ou=People,dc=dbs,dc=local'
eu student 'ldapsearch -x -LLL -H ldaps://$(hostname) -b ou=People,dc=dbs,dc=local -D uid=charlie,ou=People,dc=dbs,dc=local -w charlie'

c 'Дэйв тестирует аутентификацию в LDAP по методу поиск+связывание. Внесем в дополнительный файл HBA разрешение на аутентификацию в LDAP в режиме поиск+связывание.'
eu student "echo 'hostssl all charlie samehost ldap ldapurl=\"ldaps://dbs.local/ou=people,dc=dbs,dc=local?uid?sub\"' | sudo -u postgres tee ${HBA}.d/pg_hba_ext.conf"
s 1 "SELECT * FROM pg_hba_file_rules WHERE address = 'samehost' \gx"
s 1 "SELECT pg_reload_conf();"

eu student 'psql "host=$(hostname) user=charlie password=charlie dbname=student" -c "\conninfo"'
eu student 'tail -3 /var/log/postgresql/postgresql-16-main.log'
c 'В режиме поиск+связывание соединение PostgreSQL осуществляется дважды: первый раз проверяется возможность связаться с LDAP от имени заданного пользователя, а второй раз выполняется поиск пользователя (роли), подключающейся к базе данных.'

P 17
###############################################################################
h 'Аутентификация в Kerberos'

c 'Необходимые настройки Kerberos произведены, учетные записи (principals) зарегистрированы. Область Kerberos - DBS.LOCAL.'
c 'Включим в дополнительный файл аутентификации правило, разрешающее Алисе аутентифицироваться в Kerberos.'
eu student "echo 'hostgssenc student alice samehost gss include_realm=0' | sudo tee ${HBA}.d/pg_hba_ext.conf"
c 'Параметр include_realm=0 приводит к тому, что из учетной записи (principal) аутентифицируемого пользователя удаляется область (realm) Kerberos. Например, alice@DBS.LOCAL преобразуется в alice, то есть, в имя учетной записи в PostgreSQL.'

c 'Перечитаем конфигурацию.'
s 1 "SELECT pg_reload_conf();"
s 1 "SELECT * FROM pg_hba_file_rules WHERE address = 'samehost' \gx"

c 'Теперь Алисе необходимо получить пропуск (TGT - Ticket Granting Ticket) для возможности подключиться. Проверим кеш.'
eu student 'klist'
c 'Кеш пуст.'

c 'Запросить пропуск можно командой kinit. Эта команда интерактивно запрашивает пароль, подтверждающий право на получение TGT. Воспользуемся заранее подготовленной таблицей ключей для Алисы чтобы не вводить пароль интерактивно:'
eu student 'kinit -kt alice.keytab alice'

c 'В результате выполнения предыдущей команды должен быть получен пропуск.'
eu student 'klist'

c 'Проверим, сможет ли Алиса запустить шифрованный сеанс с аутентификацией в Kerberos.'
eu student 'psql "host=$(hostname) user=alice password=alice dbname=student" -c "\conninfo"'
eu student 'tail -3 /var/log/postgresql/postgresql-16-main.log'

c 'Очистим кеш пропусков.'
eu student 'kdestroy'

c 'В Kerberos зарегистрирована еще одна учетная запись для обычного пользователя: bob@DBS.LOCAL. Используем его для аутентификации по методу gss с картой отображения pg_ident.conf. В случае Алисы мы просто отбросили из учетной записи имя области. Этот способ не подходит, если имеется несколько областей Kerberos (realms). Карта отображений позволяет выполнять преобразования имен пользователей с помощью регулярных выражений.'
c 'Добавим в HBA правило для Боба.'
eu student "echo 'hostgssenc student bob samehost gss map=krbmap' | sudo tee -a ${HBA}.d/pg_hba_ext.conf"

c 'Содержимое дополнительного файла HBA:'
eu student "sudo -u postgres cat ${HBA}.d/pg_hba_ext.conf"
c 'Для Боба в HBA указана карта отображения в качестве параметра map метода аутентификации gss.'

c 'Теперь создадим отображение krbmap.'
eu student "echo 'krbmap /^(.*)@DBS\.LOCAL$ \1' | sudo tee -a /etc/postgresql/16/main/pg_ident.conf"
eu student "sudo tail -1 /etc/postgresql/16/main/pg_ident.conf"

c 'Перечитаем конфигурацию.'
s 1 "SELECT pg_reload_conf();"
s 1 "SELECT * FROM pg_hba_file_rules WHERE address = 'samehost' \gx"

c 'Проверим валидность записей в pg_ident.conf'
s 1 "SELECT * FROM pg_ident_file_mappings;"

c 'Получим пропуск Kerberos для Боба.'
eu student 'kinit -kt bob.keytab bob'
eu student 'klist'

c 'Боб входит в сеанс...'
eu student 'psql "host=$(hostname) user=bob password=bob dbname=student" -c "\conninfo"'
eu student 'tail -3 /var/log/postgresql/postgresql-16-main.log'

c 'Очистим кеш пропусков.'
eu student 'kdestroy'

stop_here
###############################################################################

demo_end

