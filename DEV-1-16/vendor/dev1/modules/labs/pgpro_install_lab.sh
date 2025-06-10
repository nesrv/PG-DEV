#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Размер кеша'

c 'Текущее значение параметра:'
s 1 "SHOW shared_buffers;"

c 'Задаем на 10% больше:'
# unit = 8kB
s 1 "ALTER SYSTEM SET shared_buffers='$(s_bare 1 "select pg_size_pretty(1.1*8*1024*setting::bigint) from pg_settings where name='shared_buffers';")';"

c 'Перезапуск и проверка:'
psql_close 1
pgctl_restart A
psql_open A 1

s 1 "SHOW shared_buffers;"

###############################################################################
h '2. Тест pgbench'

c 'Инициализируем pgbench в отдельной базе данных'
s 1 "CREATE DATABASE $TOPIC_DB;"
e "${BINPATH_A}pgbench -i $TOPIC_DB"

c 'Включаем вывод в журнал:'
#eu postgres "echo log_min_duration_statement=0 > $PGDATA_A/conf.d/install.conf"
e "sudo bash -c 'echo log_min_duration_statement=0 > $PGDATA_A/conf.d/install.conf'"

pgctl_reload A
c 'Проверяем значение параметра:'
s 1 "SHOW log_min_duration_statement;"

c 'Тест на 90 секунд'
e "${BINPATH_A}pgbench -T 90 -P 10 $TOPIC_DB"

###############################################################################
h '3. Просмотр журнала и отчет pgBadger'

c "Файлы журнала сообщений находятся в $LOG_A"
e "sudo ls -Ct $LOG_A"

c "Несколько последних записей журнала"

e "sudo tail $LOG_A/$(sudo ls -1t $LOG_A | head -1)"

c 'pgBadger уже установлен в виртуальной машине:'
e "pgbadger --version"

c 'Утилите нужно передать:'
ul 'имя html-файла для отчета'
ul 'формат журнала сообщений'
ul 'файл журнала или список файлов'

c 'Запускаем:'
e "sudo pgbadger --outfile=/tmp/out.html --format=stderr `sudo bash -c "ls -d1t $LOG_A/* | head -1"`"

c 'Утилита сгенерировала отчет в файле out.html.'
e "ls -l /tmp/out.html"

c 'Заглянем в отчет:'
open-file '/tmp/out.html'

###############################################################################

stop_here
cleanup
