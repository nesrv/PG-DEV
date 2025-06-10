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
h '2. Настройка непрерывной архивации'

eu student "sudo -u postgres mkdir $H/archive"

s 1 '\c - postgres'
s 1 'ALTER SYSTEM SET archive_mode = on;'
s 1 "ALTER SYSTEM SET archive_command = '[ -f $H/archive/%f ] || cp %p $H/archive/%f';"

psql_close 1
pgctl_restart A

###############################################################################
h '3. Базовая резервная копия'

c 'Поскольку нам потребуется восстанавливаться из одной копии два раза, сделаем ее в формате tar со сжатием.'
e "pg_basebackup --wal-method=none --format=tar --gzip --pgdata=/home/$OSUSER/tmp/backup"

e "ls -l /home/$OSUSER/tmp/backup"

###############################################################################
h '4. Добавление строк в таблицу'

psql_open A 1 -d $TOPIC_DB
s 1 "INSERT INTO t VALUES ('Еще одна строка');"
s 1 '\c - postgres'

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

c "Восстановились все строки. Поскольку по умолчанию применяются все имеющиеся журнальные записи, сервер сразу перешел в обычный режим и готов принимать запросы на изменение данных:"
s 2 "SELECT pg_is_in_recovery();"

###############################################################################
h '6. Восстановление из базовой резервной копии — immediate'

psql_close 2
pgctl_stop B

eu student  "sudo -u postgres  rm -rf $PGDATA_B"
eu student  "sudo -u postgres  mkdir $PGDATA_B"
eu student  "sudo -u postgres  chmod 700 $PGDATA_B"
eu student  "sudo tar xzf /home/$OSUSER/tmp/backup/base.tar.gz -C $PGDATA_B"

c 'Создаем recovery.signal, в конфигурационный файл записываем команду восстановления и целевую точку:'
e "sudo -u postgres touch $PGDATA_B/recovery.signal"

e "cat << EOF | sudo -u postgres tee $PGDATA_B/postgresql.auto.conf
restore_command = 'cp $H/archive/%f %p'
recovery_target = 'immediate'
EOF
"

c 'Запускаем сервер.'
pgctl_start B

psql_open B 2 -p 5433 -d $TOPIC_DB
s 2 "SELECT * FROM t;"
c 'Восстановилась только первая строка.'

c "На этот раз были применены только журнальные записи, необходимые для согласования данных. Сервер уже принимает запросы на чтение, при необходимости восстановление можно продолжить:"
s 2 "SELECT pg_is_in_recovery(), pg_get_wal_replay_pause_state();"

c 'Функция pg_get_wal_replay_pause_state() возвращает:'
ul 'not paused — приостановка не запрашивалась;'
ul 'pause requested — запрошена приостановка;'
ul 'paused — восстановление приостановлено.'

c "Поскольку нам не нужно применять последующие записи, завершаем восстановление, переводя сервер в обычный режим (нужны права суперпользователя):"
s 2 "\c - postgres"
s 2 "SELECT pg_wal_replay_resume();"
wait_sql 2 "SELECT not pg_is_in_recovery();"
s 2 "SELECT pg_is_in_recovery();"

c "Чтобы не выходить из режима восстановления вручную, можно было заранее задать значение recovery_target_action = 'promote'."

###############################################################################
stop_here
cleanup
demo_end
