#!/bin/bash

. ../lib
init

start_here 8

###############################################################################
h 'Проверка системы после установки'

c "В виртуальной машине курса установлен пакет postgrespro-ent-$VERSION_A-server, исполняемые файлы находятся в каталоге /opt/pgpro/ent-$VERSION_A/bin:"
e "ls -C $BINPATH_A"
p
c 'Для инициализации кластера была использована утилита pg-setup:'
e_fake "sudo ${BINPATH_A}pg-setup initdb -g -D $PGDATA_A --auth=trust"
p
CONTROL_SAVE=$CONTROL_A
c 'Этой же утилитой pg-setup была настроена служба с автозапуском, так что экземпляром можно управлять в стиле ОС:'
export CONTROL_A=systemctl
pgctl_status A

c 'Статус можно узнать и с помощью традиционной утилиты pg_ctl:'
export CONTROL_A=pg_ctl
pgctl_status A
export CONTROL_A=$CONTROL_SAVE

c 'Для запуска, остановки, перезапуска экземпляра сервера рекомендуется использовать те средства, которые уже используются в вашей компании.'
p

c 'Информацию об установленной системе (номер версии и название редакции) можно узнать разными способами, например, с помощью утилиты pg_config или SQL-функций:'
s 1 "SELECT pgpro_edition(), pgpro_version() \gx"

c 'Можно вывести значения конфигурационных параметров SQL-командой SHOW, как это делается в обычном PostgreSQL:'
s 1 "SHOW data_checksums;
   SHOW data_directory;"

c 'Файл postgresql.conf находится в каталоге данных:'
s 1 "SHOW config_file;"

c 'Директива include_dir добавляет к конфигурации содержимое всех файлов *.conf подкаталога conf.d. Это позволяет менять значения параметров и возвращаться к прежним значениям, не меняя основной файл конфигурации. В виртуальной машине директива добавлена в основной конфигурационный файл Postgres Pro Enterprise:'

e "grep '^include_dir' $(s_bare 1 'SHOW config_file;')" conf

psql_close 1

###############################################################################
P 13
h "Перенос данных из PostgreSQL"

c 'При миграции из PostgreSQL можно использовать средства логического резервного копирования или утилиту pg_upgrade.'

c "В виртуальной машине установлен PostgreSQL $VERSION_V и инициализирован кластер $CLUSTER_V. Запустим экземпляр."

pgctl_start V

c 'В отдельной базе данных создадим таблицу:'

# Используем psql от pgpro т.к. путь не показывается
BINPATH_V=$BINPATH_E psql_open V 1
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE TABLE test(s) AS VALUES('Строка из PostgreSQL');"

c 'Остановим экземпляр PostgreSQL.'
pgctl_stop V

c 'Будем переносить данные с помощью pg_upgrade. Нам понадобится пустой кластер Postgres Pro Enterprise.'

e "sudo mkdir ${PGDATA_E}"
e "sudo chown postgres: ${PGDATA_E}"
eu postgres "${BINPATH_E}initdb -D ${PGDATA_E} --auth=trust"

p
c 'Для начала запустим утилиту в режиме проверки. Ключами -b и -B нужно указать пути к исполняемым файлам нового и старого кластера, а ключами -d и -D — пути к postgresql.conf.'

eu postgres "${BINPATH_E}pg_upgrade --check -b ${BINPATH_V} -B ${BINPATH_E} -d /etc/postgresql/16/prod -D ${PGDATA_E}"

# *******************************
#c 'Обнаружилась проблема: у исходного и целевого кластеров разные настройки для правила сортировки по умолчанию.'

########################################################################
P 15

# *******************************
# Все получается и так. Сломать заранее специально?
# *******************************
#c 'PostgreSQL на уровне кластера и базы данных допускает только правила сортировки провайдера libc (icu поддерживается с версии 15), поэтому придется заново инициализировать кластер Postgres Pro Enterprise с правилом сортировки en_US.UTF-8@libc.'
#eu postgres "rm -rf ${PGDATA_E}/*"
#eu postgres "${BINPATH_E}initdb -D ${PGDATA_E} --auth=trust --locale=en_US.UTF-8@libc"
#p

#c 'Еще раз запустим pg_upgrade в режиме проверки:'

#eu postgres "${BINPATH_E}pg_upgrade --check -b ${BINPATH_V} -B ${BINPATH_E} -d /etc/postgresql/16/prod -D ${PGDATA_E}"
# *******************************

c 'Все в порядке, можно переносить данные.'

eu postgres "${BINPATH_E}pg_upgrade -b ${BINPATH_V} -B ${BINPATH_E} -d /etc/postgresql/16/prod -D ${PGDATA_E}"

p

c 'Задаем порт и запускаем сервер Postgres Pro Enterprise.'
eu postgres "echo \"include_dir='conf.d'\" >> ${PGDATA_E}/postgresql.conf"
eu postgres "mkdir ${PGDATA_E}/conf.d"
eu postgres "echo port=${PORT_E} > ${PGDATA_E}/conf.d/install.conf"
pgctl_start E

psql_open E 2 -d ${TOPIC_DB}
s 2 "SELECT pgpro_version();"
s 2 "SELECT * FROM test;"

c 'Данные перенесены в Postgres Pro Enterprise.'

########################################################################

stop_here
cleanup
demo_end
