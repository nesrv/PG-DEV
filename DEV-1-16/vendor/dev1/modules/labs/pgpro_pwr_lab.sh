#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Подготовка СУБД для работы с расширением pgpro_pwr'

psql_open A 1

c 'Подключим разделяемые библиотеки.'
c 'Расширение pgpro_pwr получает сводную статистику ожиданий от расширения pg_wait_sampling:'
s 1 "ALTER SYSTEM SET shared_preload_libraries = pg_wait_sampling, pgpro_stats;"

c 'Параметр track_io_timing нужен для анализа времени, затраченного операторами на чтение или запись блоков:'
s 1 "ALTER SYSTEM SET track_io_timing = 'on';"

c 'Параметр track_functions позволяет отслеживать вызовы пользовательских функций:'
s 1 "ALTER SYSTEM SET track_functions = 'all';"

c 'Перезагрузим сервер.'
pgctl_restart A

p
###############################################################################
h '2. Создание базы данных и установка расширения pgpro_pwr'

psql_open A 1

c 'Создадим базу данных.'
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Создадим схему для хранения объектов расширения и установим расширение.'
s 1 "CREATE SCHEMA profile;"
s 1 "CREATE EXTENSION pgpro_pwr SCHEMA profile CASCADE;"
s 1 "CREATE EXTENSION pg_wait_sampling;"
s 1 'CREATE EXTENSION pgpro_stats;'
s 1 "\dx"

p
###############################################################################
h '3. Нагрузочное тестирование'

c 'Сделаем выборку:'
s 1 "SELECT * FROM profile.take_sample();"

c 'Инициализируем нагрузочные таблицы pgbench:'
e "${BINPATH_A}pgbench -i $TOPIC_DB"

c 'Запустим pgbench на 30 секунд:'
e "${BINPATH_A}pgbench -T30 $TOPIC_DB"

c 'Получим вторую выборку, в которую попадут данные о нагрузке при инициализации и нагрузочном тесте:'
s 1 "SELECT * FROM profile.take_sample();"

p
###############################################################################
h '4. Создание нового табличного пространства'

c 'Создадим табличное пространство.'
eu postgres "mkdir /var/lib/postgresql/ts_dir"
s 1 "CREATE TABLESPACE ts_idx LOCATION '/var/lib/postgresql/ts_dir';"

c 'Сделаем выборку:'
s 1 "SELECT * FROM profile.take_sample();"

p
###############################################################################
h '5. Нагрузочное тестирование при размещении индексов в отдельном табличном пространстве'

c 'Инициализируем нагрузочные таблицы pgbench:'
e "${BINPATH_A}pgbench -i --index-tablespace=ts_idx $TOPIC_DB"

c 'Запустим pgbench на 30 секунд:'
e "${BINPATH_A}pgbench -T30 $TOPIC_DB"

c 'Получим еще одну выборку:'
s 1 "SELECT * FROM profile.take_sample();"

c 'Получим список выборок:'
s 1 "SELECT * FROM profile.show_samples();"

p
###############################################################################
h '5. Получение разностного отчета'

c 'Получим разностный отчет.'
[ -e /tmp/report_diff.html ] && sudo rm /tmp/report_diff.html
e "psql -d $TOPIC_DB -Aqtc \"SELECT profile.get_diffreport(1,2,3,4)\" -o /tmp/report_diff.html"
open-file "/tmp/report_diff.html"

###############################################################################

stop_here
cleanup
