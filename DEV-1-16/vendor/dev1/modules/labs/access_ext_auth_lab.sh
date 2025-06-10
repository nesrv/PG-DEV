#!/bin/bash


. ../lib
init
kdestroy

export HBA=`s_bare 1 "SHOW hba_file;"`
export IDT=`s_bare 1 "SHOW ident_file;"`
local1st=$(psql -At -c "select min(line_number) from pg_hba_file_rules where type = 'local'")

start_here
###############################################################################
h '1. Аутентификация peer'

c 'Подготовим PostgreSQL для записи в журнал отчета сообщений о подключениях.'
s 1 "ALTER SYSTEM SET log_connections TO on;"
s 1 "SELECT pg_reload_conf();"

c 'Зарегистрируем Алису'
s 1 'CREATE USER alice;'

c 'Добавим для alice аутентификацию по методу peer с применением отображения.'
eu student "sudo -u postgres sed -i '${local1st}i\######\nlocal student alice peer map=m1\n' ${HBA}"

c 'Результат редактирования pg_hba.conf'
eu student "sudo -u postgres sed -n '${local1st},\$p' ${HBA}"

c 'Проверим правильность HBA записи для Алисы:'
s 1 "SELECT * FROM pg_hba_file_rules WHERE 'alice' = ANY(user_name) \gx"

c 'Подготовим отображение для alice в pg_ident.conf'
eu student "echo 'm1 student alice' | sudo -u postgres tee ${IDT}"
s 1 "SELECT * FROM pg_ident_file_mappings;"
s 1 "SELECT pg_reload_conf();"

c 'Проверим, сможет ли Алиса подключиться...'
eu student 'psql "user=alice dbname=student" -c "\conninfo"'
eu student 'tail -3 /var/log/postgresql/postgresql-16-main.log'

c 'Удалим запись для Алисы из pg_ident.conf'
eu student "sudo -u postgres sed -i '/alice/d' ${IDT}"

p
###############################################################################
h '2. Простое связывание LDAP'

c 'Зарегистрируем роль Боб'
s 1 'CREATE USER bob;'

c 'Заменим запись в pg_hba.conf для Алисы настройкой для аутентификации Боба в LDAP по методу простого связывания.'
eu student "sudo -u postgres sed -i 's/^.*alice.*$/host all bob samehost ldap ldapurl=\"ldap:\/\/dbs.local\/dc=dbs,dc=local?cn?sub\" ldaptls=1/' ${HBA}"

c 'Результат редактирования pg_hba.conf'
eu student "sudo -u postgres sed -n '${local1st},\$p' ${HBA}"
s 1 "SELECT * FROM pg_hba_file_rules WHERE 'bob' = ANY(user_name) \gx"
s 1 "SELECT pg_reload_conf();"

c 'Проверим возможность подключиться:'
eu student 'psql "host=localhost user=bob password=bob dbname=student" -c "\conninfo"'
eu student 'tail -3 /var/log/postgresql/postgresql-16-main.log'

p
###############################################################################
h '3. Аутентификация gss'

c 'Настроим PostgreSQL для прослушивания всех интерфейсов'
s 1 "ALTER SYSTEM SET listen_addresses = '*';"

psql_close 1
pgctl_restart A
PSQL_PROMPT1='student=# '
psql_open A 1 student

c 'Зарегистрируем роль Чарли'
s 1 'CREATE USER charlie;'

c 'Включим в pg_hba.conf правило, разрешающее Чарли аутентифицироваться в Kerberos.'
eu student "sudo -u postgres sed -i 's/^.*bob.*$/host all charlie samehost gss map=m2/' ${HBA}"

c 'Получившееся содержимое pg_hba.conf'
eu student "sudo -u postgres sed -n '${local1st},\$p' ${HBA}"

c 'Подготовим отображение для charlie в pg_ident.conf'
eu student "echo 'm2 /^(.*)@DBS\.LOCAL$ \1' | sudo -u postgres tee -a ${IDT}"

c 'Перечитаем конфигурацию.'
s 1 "SELECT pg_reload_conf();"
s 1 "SELECT * FROM pg_hba_file_rules WHERE 'charlie' = ANY(user_name) \gx"

c 'Проверим валидность записей в pg_ident.conf'
s 1 "SELECT * FROM pg_ident_file_mappings;"

c 'Очистим кеш пропусков.'
eu student 'kdestroy'

c 'Получим пропуск Kerberos для Чарли.'
eu_fake_p student 'kinit charlie'
echo 'Password for charlie@DBS.LOCAL:'
kinit -kt ~student/bob.keytab bob # На самом деле это Чарли

eu_fake_p student 'klist'
klist | sed 's/bob/charlie/g'

c 'Боб входит в сеанс...'
eu_fake_p student 'psql "host=$(hostname) user=charlie dbname=student" -c "\conninfo"'
sudo -u postgres sed -i 's/^.*charlie.*$/host all bob samehost gss map=m2/' ${HBA} # Чарли будет изображен Бобом
sudo pkill -HUP postgres
psql "host=$(hostname) user=bob dbname=student" -c "\conninfo" | sed 's/bob/charlie/g'
eu_fake_p student 'tail -3 /var/log/postgresql/postgresql-16-main.log'
tail -3 /var/log/postgresql/postgresql-16-main.log | sed 's/bob/charlie/g'

sudo -u postgres sed -i 's/^.*bob.*$/host all charlie samehost gss map=m2/' ${HBA} # Обратный фокус
sudo pkill -HUP postgres

c 'Очистим кеш пропусков.'
eu student 'kdestroy'

stop_here
###############################################################################

demo_end

