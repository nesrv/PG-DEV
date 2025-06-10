#!/bin/bash

. ../lib
init


start_here

###############################################################################
h '1a. Full page writes = on'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE EXTENSION pg_walinspect;"

e "pgbench -i $TOPIC_DB"

s 1 "SHOW full_page_writes;"
s 1 "CHECKPOINT;"

c 'Запускаем тест на 30 секунд.'

s 1 "SELECT pg_current_wal_insert_lsn();"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

e "pgbench -T 30 $TOPIC_DB"

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'Размер журнальных записей:'

s 1 "SELECT pg_size_pretty('$END_LSN'::pg_lsn - '$START_LSN'::pg_lsn);"

c 'Значительную часть объема журнала составляют полные образы страниц (FPI):'

s 1 "SELECT pg_walfile_name('$START_LSN'), pg_walfile_name('$END_LSN');"
export SEGMENTS=$(s_bare 1 "SELECT pg_walfile_name('$START_LSN')||' '||pg_walfile_name('$END_LSN');")
e "sudo ${BINPATH_A}pg_waldump --stats=record -p $PGDATA_A/pg_wal -s '$START_LSN' -e '$END_LSN' $SEGMENTS"

c 'Обратите внимание на общий размер (строка Total) полных образов (столбец FPI size).'

s 1 "SELECT \"resource_manager/record_type\", count, record_size, fpi_size, combined_size
   FROM pg_get_wal_stats('$START_LSN', '$END_LSN')
   UNION ALL
   SELECT 'Total', sum(count), sum(record_size), sum(fpi_size), sum(combined_size) 
   FROM pg_get_wal_stats('$START_LSN', '$END_LSN');"

###############################################################################
h '1b. Full page writes = off'

s 1 "ALTER SYSTEM SET full_page_writes = off;"
s 1 "SELECT pg_reload_conf();"
s 1 "CHECKPOINT;"

c 'Запускаем тест на 30 секунд.'

s 1 "SELECT pg_current_wal_insert_lsn();"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

e "pgbench -T 30 $TOPIC_DB"

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'Размер журнальных записей:'

s 1 "SELECT pg_size_pretty('$END_LSN'::pg_lsn - '$START_LSN'::pg_lsn);"

c 'Размер уменьшился.'

s 1 "SHOW data_checksums;"

c 'Кластер был инициализирован с контрольными суммами в страницах. Поэтому несмотря на то, что full_page_writes выключен, в журнал все равно записываются полные образы страниц при изменении битов подсказок, но теперь объем этих данных незначителен — строка XLOG/FPI_FOR_HINT:'

s 1 "SELECT pg_walfile_name('$START_LSN'), pg_walfile_name('$END_LSN');"
export SEGMENTS=$(s_bare 1 "SELECT pg_walfile_name('$START_LSN')||' '||pg_walfile_name('$END_LSN');")
e "sudo ${BINPATH_A}pg_waldump --stats=record -p $PGDATA_A/pg_wal -s '$START_LSN' -e '$END_LSN' $SEGMENTS"

s 1 "SELECT \"resource_manager/record_type\", count, record_size, fpi_size, combined_size
   FROM pg_get_wal_stats('$START_LSN', '$END_LSN')
   UNION ALL
   SELECT 'Total', sum(count), sum(record_size), sum(fpi_size), sum(combined_size) 
   FROM pg_get_wal_stats('$START_LSN', '$END_LSN');"

###############################################################################
h '2. Сжатие'

s 1 "ALTER SYSTEM SET full_page_writes = on;"
s 1 "ALTER SYSTEM SET wal_compression = on;"
s 1 "SELECT pg_reload_conf();"
s 1 "CHECKPOINT;"

c 'Запускаем тест на 30 секунд.'

s 1 "SELECT pg_current_wal_insert_lsn();"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

e "pgbench -T 30 $TOPIC_DB"

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'Размер журнальных записей:'

s 1 "SELECT pg_size_pretty('$END_LSN'::pg_lsn - '$START_LSN'::pg_lsn);"

c 'В данном случае — при наличии большого числа полных образов страниц — размер журнальных записей уменьшился примерно в два раза. Хотя включение сжатия и нагружает процессор, практически наверняка им стоит воспользоваться при включенных контрольных суммах.'

###############################################################################

stop_here
cleanup
