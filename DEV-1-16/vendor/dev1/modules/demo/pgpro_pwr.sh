#!/bin/bash

. ../lib
init

start_here 6

###############################################################################
h 'Установка расширения pgpro_pwr'

c 'Создадим тестовую базу данных на основе demo:'
psql_open A 1
s 1 "CREATE DATABASE $TOPIC_DB TEMPLATE demo;"

c 'Для удобства настроим путь поиска:'
s 1 "ALTER DATABASE $TOPIC_DB SET search_path TO bookings, public;"

c 'Пакет расширения pgpro_pwr уже установлен в виртуальной машине.'

c 'Добавим загрузку библиотек вспомогательных расширений и зададим параметры сбора статистики.'
s 1 "ALTER SYSTEM SET shared_preload_libraries = pg_wait_sampling, pgpro_stats;"
s 1 "ALTER SYSTEM SET track_io_timing = 'on';"
s 1 "ALTER SYSTEM SET track_functions = 'all';"

c 'Перезагрузим сервер.'
pgctl_restart A

psql_open A 1 -p 5432 -d $TOPIC_DB
c 'Создадим схему для объектов расширения и добавим расширение в базу данных.'
s 1 "CREATE SCHEMA profile;"
s 1 'CREATE EXTENSION pgpro_stats;'
s 1 "CREATE EXTENSION pgpro_pwr SCHEMA profile CASCADE;"
s 1 "CREATE EXTENSION pg_wait_sampling;"
s 1 "\dx"

P 10
###############################################################################

h 'Получение выборки и создание выборочной линии'

c 'Откроем второй сеанс.'
psql_open A 2 -p 5432 -d $TOPIC_DB

c 'Получим первую выборку. Предыдущая статистика сбрасывается.'
s 1 "SELECT * FROM profile.take_sample();"

c 'Используем пример соединения хешированием из учебного курса QPT.'
c 'Во втором сеансе выполним транзакцию, выделив недостаточный объем оперативной памяти; двухпроходное хеш-соединение будет использовать временные файлы:'
s 2 "BEGIN;"
s 2 "SET LOCAL work_mem = '12MB';"
s 2 "SET LOCAL hash_mem_multiplier = 1;"
s 2 "EXPLAIN (analyze, buffers, costs off, timing off, summary off)
SELECT * FROM bookings b
  JOIN tickets t ON b.book_ref = t.book_ref;"
s 2 "COMMIT;"

c 'Получим вторую выборку — в нее попадут данные о нагрузке после первой выборки:'
s 1 "SELECT * FROM profile.take_sample();"

c 'Теперь во втором сеансе выполним транзакцию, выделив достаточно рабочей памяти для хеш-соединения:'
s 2 "BEGIN;"
s 2 "SET LOCAL work_mem = '48MB';"
s 2 "SET LOCAL hash_mem_multiplier = 3;"
s 2 "EXPLAIN (analyze, buffers, costs off, timing off, summary off)
SELECT * FROM bookings b
  JOIN tickets t ON b.book_ref = t.book_ref;"
s 2 "COMMIT;"

c 'А сейчас получим третью выборку — в нее попадут данные о нагрузке после второй выборки:'
s 1 "SELECT * FROM profile.take_sample();"

c 'Список выборок:'
s 1 "SELECT * FROM profile.show_samples();"

c 'Сформируем из имеющихся выборок две выборочные линии.'
s 1 "SELECT profile.create_baseline(baseline=>'BaseLine1', start_id=>1, end_id=>2);"
s 1 "SELECT profile.create_baseline(baseline=>'BaseLine2', start_id=>2, end_id=>3);"

c 'Список выборочных линий:'
s 1 "SELECT * FROM profile.show_baselines();"

P 13
###############################################################################

h 'Отчеты'

c 'Получим отчет. Для построения обычного отчета достаточно указать две выборки или одну выборочную линию.'
c 'В плане запроса, выполненного в условиях недостатка рабочей памяти, видно, что используются временные файлы для двухпроходного хеш-соединения.'
c 'Раздел отчета "Top SQL by temp usage" должен содержать сведения об этом запросе.'
e "psql -d $TOPIC_DB -Aqtc 'SELECT profile.get_report(1,2)' -o /tmp/report_1_2.html"
open-file "/tmp/report_1_2.html"

c 'Получим разностный отчет. Используем две выборочные линии.'
c 'В разностном отчете должно быть заметно, что во втором запросе рабочей памяти хватило для выполнения однопроходного хеш-соединения и временные файлы не использовались.'
c 'В отчете просмотрите разделы:'
ul 'Top SQL by temp usage;'
ul 'Load distribution among heavily loaded databases;'
ul 'Load distribution.'
[ -e /tmp/report_diff.html ] && sudo rm /tmp/report_diff.html
e "psql -d $TOPIC_DB -Aqtc \"SELECT profile.get_diffreport('BaseLine1','BaseLine2')\" -o /tmp/report_diff.html"
#s 1 "COPY (SELECT profile.get_diffreport('BaseLine1','BaseLine2')) TO '/tmp/report_diff.html';"
open-file "/tmp/report_diff.html"

###############################################################################

stop_here
cleanup
demo_end
