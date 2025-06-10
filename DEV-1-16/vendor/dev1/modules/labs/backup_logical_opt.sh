#!/bin/bash

. ../lib
init

#pgctl_start B

start_here
###############################################################################
h '1. COPY HEADER'

c 'Таблица с двумя столбцами.'
s 1 "CREATE DATABASE db1;"
s 1 "\c db1"
s 1 "CREATE TABLE t(f1 integer, f2 text DEFAULT 'Some string');"
s 1 "INSERT INTO t VALUES (1,'One'), (2,'Two'), (3,NULL);"

c 'Выгрузка данных из таблицы с заголовком.'
s 1 "COPY t TO '/tmp/twh.data' WITH (HEADER true);"

c 'Выгруженные данные:'
s 1 "\! cat /tmp/twh.data"

c 'Очистим таблицу и загрузим данные, установив значение по умолчанию.'
s 1 "TRUNCATE TABLE t;"
s 1 "COPY t FROM '/tmp/twh.data' WITH (HEADER true, DEFAULT '\N', NULL '\NULL');"
s 1 "SELECT * FROM t;"

c 'Снова очистим таблицу, изменим заголовок с названием второго столбца и загрузим данные.'
eu student "sudo -u postgres sed -i '1s/f2/f3/' /tmp/twh.data"
s 1 "\! cat /tmp/twh.data"
s 1 "TRUNCATE TABLE t;"
s 1 "COPY t FROM '/tmp/twh.data' WITH (HEADER true, DEFAULT '\N', NULL '\NULL');"
s 1 "SELECT * FROM t;"
c 'Не смотря на то, что название столбца в заголовке входного файла не совпадает с названием столбца таблицы, загрузка прошла успешно.'

c 'Попробуем сделать то же самое, но с добавлением параметра MATCH.'
s 1 "TRUNCATE TABLE t;"
s 1 "COPY t FROM '/tmp/twh.data' WITH (HEADER MATCH);"

c 'С параметром MATCH имена столбцов в заголовке загружаемых данных должны совпадать с именами столбцов таблицы.'
s 1 "ALTER TABLE t DROP f2;"
s 1 "ALTER TABLE t ADD f3 text;"
s 1 "COPY t FROM '/tmp/twh.data' WITH (HEADER MATCH);"
s 1 "SELECT * FROM t;"
eu student 'sudo rm /tmp/twh.data'

###############################################################################
h '2. Исследование сжатия в pg_dump'

c 'Подготовка данных для загрузки.'
#eu student "base32 -w0 < /usr/lib/postgresql/16/bin/postgres > /tmp/16MB.text"
eu student "base32 -w0 < ${BINPATH_A}postgres > /tmp/16MB.text"
eu student "ls -lh /tmp/16MB.text"

c 'Загрузка данных в таблицу.'
s 1 "CREATE TABLE mb (s text); COPY mb FROM '/tmp/16MB.text';"
s 1 "SELECT pg_size_pretty(pg_table_size('mb'));"

c 'Проверим время, потребное на выгрузку данных без сжатия (а также прогреем кеш).'
eu student "time pg_dump -Fc -d db1 -Z none -f ~/tmp/db1.none"

c 'Сколько потребуется времени на выгрузку со сжатием gzip (используется по умолчанию)?'
eu student "time pg_dump -Fc -d db1 -Z gzip -f ~/tmp/db1.gz"

c 'Теперь испытаем lz4.'
eu student "time pg_dump -Fc -d db1 -Z lz4 -f ~/tmp/db1.lz4"

c 'А теперь - zstd.'
eu student "time pg_dump -Fc -d db1 -Z zstd -f ~/tmp/db1.zstd"

c 'Сравним размеры полученных копий:'
eu student "ls -lhS ~/tmp/db1.*"
eu student "rm ~/tmp/db1.*"

###############################################################################
stop_here
cleanup
demo_end
