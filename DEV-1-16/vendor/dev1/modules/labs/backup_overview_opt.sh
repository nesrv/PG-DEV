#!/bin/bash

. ../lib

init
start_here

###############################################################################
h '1. Потоковый архив'

c 'Обратите внимание, что часть команд выполняется от имени пользователя postgres, а часть — от имени student.'

c 'Создаем каталог для архива WAL:'
eu postgres "mkdir ${H}/archive"

c "Создаем слот, чтобы в архиве не было пропусков:"
eu postgres "pg_receivewal --create-slot --slot=archive"

c "Запускаем утилиту pg_receivewal в фоновом режиме. Для этого следующую команду нужно выполнить в отдельном окне терминала или добавить в конце командной строки символ &."
eu_runbg postgres "pg_receivewal -D ${H}/archive --slot=archive"
sleep-ni 2

e "sudo ls -l ${H}/archive"

###############################################################################
h '2. Базовая физическая копия без журнала'

backup_dir=~/tmp/backup  # очистка каталога - в init
e "pg_basebackup --wal-method=none --pgdata=$backup_dir --checkpoint=fast"
e "ls -l $backup_dir"

###############################################################################
h '3. Новые база данных и таблица'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE t(n integer);'
s 1 'INSERT INTO t VALUES (1), (2), (3);'

###############################################################################
h '4. Настройка восстановления'

c "Убеждаемся, что второй сервер остановлен, и выкладываем резервную копию:"
pgctl_status R
e "sudo rm -rf $PGDATA_R"
e "sudo mv $backup_dir $PGDATA_R"

c "При восстановлении также используем частично записанный сегмент:"
e "echo \"restore_command = 'cp ${H}/archive/%f %p || cp ${H}/archive/%f.partial %p'\" | sudo tee $PGDATA_R/postgresql.auto.conf" conf
e "touch $PGDATA_R/recovery.signal"
e "sudo chown -R postgres:postgres $PGDATA_R"

c 'Запустим сервер и проверим результат:'
pgctl_start R
psql_open R 2  -d $TOPIC_DB
s 2 'SELECT * FROM t;'

c "Архивация больше не нужна. Остановим утилиту и удалим слот, чтобы он не мешал очистке WAL."
e "sudo pkill pg_receivewal"
wait_status "sudo pidwait pg_receivewal" 1
eu postgres "pg_receivewal --drop-slot --slot=archive"

###############################################################################
stop_here
cleanup
demo_end
