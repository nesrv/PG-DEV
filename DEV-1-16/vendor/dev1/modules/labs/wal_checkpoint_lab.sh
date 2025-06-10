#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Настройка контрольной точки'

s 1 "ALTER SYSTEM SET checkpoint_timeout = '30s';"
s 1 "ALTER SYSTEM SET min_wal_size = '16MB';"
s 1 "ALTER SYSTEM SET max_wal_size = '16MB';"

s 1 "SELECT pg_reload_conf();"

###############################################################################
h '2. Нагрузка'

c 'Инициализируем таблицы.'

s 1 "CREATE DATABASE $TOPIC_DB;"

e "pgbench -i $TOPIC_DB"

c 'Сбросим статистику.'

s 1 "SELECT pg_stat_reset_shared('bgwriter');"

c 'Запускаем pgbench, предварительно запомнив позицию в журнале.'

s 1 "SELECT pg_current_wal_insert_lsn();"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

e "pgbench -T 180 -R 100 $TOPIC_DB"

###############################################################################
h '3. Объем журнальных файлов'

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")
s 1 "SELECT pg_size_pretty('$END_LSN'::pg_lsn - '$START_LSN'::pg_lsn);"

###############################################################################
h '4. Статистика'

s 1 "SELECT checkpoints_timed, checkpoints_req FROM pg_stat_bgwriter;"

c 'Несмотря на то что в среднем объем журнальных записей за контрольную точку не превосходит установленного предела, часть контрольных точек выполнялась не по расписанию. Это говорит о неравномерности потока журнальных записей (вызванной выполнением автоочистки и другими причинами).'
c 'Поэтому в реальной системе замеры лучше выполнять на достаточно больших интервалах времени.'

###############################################################################
h '5. Настройки по умолчанию'

s 1 "ALTER SYSTEM RESET ALL;"
s 1 "SELECT pg_reload_conf();"

###############################################################################

stop_here
cleanup
