#!/bin/bash

. ../lib
init

start_here
###############################################################################
h '1. База данных и таблица'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE t(s text);'
s 1 "INSERT INTO t VALUES ('Привет, мир!');"

###############################################################################
h '2. Подключение модуля архивирования WAL и настройка архивации.'

c 'Архив сегментов WAL'
eu student "sudo -u postgres mkdir $H/archive"

c 'Добавим необходимую конфигурацию для модуля архивирования в каталог дополнительной конфигурации.'
e "cat << EOF | sudo -u postgres tee $CONF_A/conf.d/arch.conf
archive_mode = 'on'
archive_library = 'basic_archive'
basic_archive.archive_directory = '$H/archive'
EOF
"

psql_close 1
pgctl_restart A

###############################################################################
h '3. Базовая резервная копия'

c 'Копия в формате tar со сжатием.'
e "pg_basebackup -Xn -Ft --gzip -D /home/$OSUSER/tmp/backup"

e "ls -l /home/$OSUSER/tmp/backup"

###############################################################################
h '4. Добавление строк в таблицу'

psql_open A 1 -d $TOPIC_DB -U postgres

s 1 "INSERT INTO t VALUES ('Еще одна строка');"

c 'Переключаем сегмент:'
s 1 "SELECT pg_walfile_name(pg_current_wal_lsn()), pg_switch_wal();"

c 'Проверяем статус архивации:'
s 1 'SELECT last_archived_wal FROM pg_stat_archiver;'

###############################################################################
h '5. Восстановление из базовой резервной копии'

pgctl_stop B
eu student  "sudo -u postgres  rm -rf $PGDATA_B"
eu student  "sudo -u postgres  mkdir $PGDATA_B"
eu student  "sudo -u postgres  chmod 700 $PGDATA_B"
eu student  "sudo tar xzf /home/$OSUSER/tmp/backup/base.tar.gz -C $PGDATA_B"

c 'Для простоты отключим непрерывное архивирование на резервном сервере и укажем только команду восстановления:'
e "echo \"restore_command = 'cp $H/archive/%f %p' \" | sudo -u postgres tee $PGDATA_B/postgresql.auto.conf"

c 'Создаем recovery.signal.'
e "sudo -u postgres touch $PGDATA_B/recovery.signal"

c 'Запускаем сервер.'
pgctl_start B

psql_open B 2 -p 5433 -d $TOPIC_DB
s 2 "SELECT * FROM t;"

###############################################################################
stop_here
cleanup
demo_end
