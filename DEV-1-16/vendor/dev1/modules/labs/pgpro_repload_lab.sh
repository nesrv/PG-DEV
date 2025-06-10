#!/bin/bash

. ../lib
init

start_here
###############################################################################

h '1.Подготовка СУБД для работы с расширением pgpro_pwr.'

psql_open A 1

c 'Подключим разделяемые библиотеки.'
c 'Расширение pgpro_pwr получает сводную статистику ожидания от расширения pg_wait_sampling.'
s 1 "ALTER SYSTEM SET shared_preload_libraries = pg_wait_sampling, pgpro_stats;"
c 'Параметр track_io_timing нужен для анализа времени, затраченного операторами на чтение или запись блоков.'
s 1 "ALTER SYSTEM SET track_io_timing = 'on';"
s 1 "ALTER SYSTEM SET track_functions = 'all';"

c 'Перезагрузим сервер.'
psql_close 1
pgctl_restart A

p
###############################################################################
h '2.Создание базы данных и установка расширения pgpro_pwr.'

psql_open A 1

c 'Создадим базу данных.'
s 1 "CREATE DATABASE testpwr;"
s 1 "\c testpwr"

c 'Создадим схему для хранения объектов расширения и установим расширение.'
s 1 "CREATE SCHEMA profile;"
s 1 "CREATE EXTENSION pgpro_pwr SCHEMA profile CASCADE;"
s 1 "CREATE EXTENSION pg_wait_sampling;"
s 1 'CREATE EXTENSION pgpro_stats;'
s 1 "\dx"

psql_close 1

p
###############################################################################
h '3.Нагрузочное тестирование.'

psql_open A 1 -p 5432 -d testpwr

c 'Сделаем выборку.'
s 1 "SELECT profile.take_sample();"

c 'Инициализируем нагрузочные таблицы pgbench.'
e "${BINPATH_A}pgbench -i testpwr"

c 'Запустим pgbench на 30с.'
e "${BINPATH_A}pgbench -T30 testpwr"

c 'Получим вторую выборку, в которой будут данные о нагрузке при инициализации и нагрузочном тесте.'
s 1 "SELECT profile.take_sample();"

psql_close 1

p
###############################################################################
h '4.Создание нового табличного пространства.'

eu postgres "mkdir /var/lib/postgresql/idx_ts"

psql_open A 1 -p 5432 -d testpwr

c 'Создадим табличное пространство.'
s 1 "CREATE TABLESPACE ts_idx LOCATION '/var/lib/postgresql/idx_ts';"

c 'Сделаем выборку.'
s 1 "SELECT profile.take_sample();"

p
###############################################################################
h '5.Нагрузочное тестирование при размещении индексов в отдельном табличном пространстве.'

c 'Инициализируем нагрузочные таблицы pgbench.'
e "${BINPATH_A}pgbench -i --index-tablespace=ts_idx testpwr"

c 'Запустим pgbench на 30с.'
e "${BINPATH_A}pgbench -T30 testpwr"

c 'Получим еще одну выборку.'
s 1 "SELECT profile.take_sample();"

c 'Получим список выборок.'
s 1 "SELECT * FROM profile.show_samples();"

p
###############################################################################
h '5.Получение разностного отчета.'

c 'Получим разностный отчет.'
[ -e /tmp/report_diff.html ] && sudo rm /tmp/report_diff.html
s 1 "COPY (SELECT profile.get_diffreport(1,2,3,4)) TO '/tmp/report_diff.html';"
ei "firefox /tmp/report_diff.html >& /dev/null"

psql_close 1

###############################################################################
stop_here

cleanup
demo_end
