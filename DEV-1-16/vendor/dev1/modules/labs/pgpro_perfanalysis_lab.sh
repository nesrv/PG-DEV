#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Подготовка СУБД для работы с расширением pgpro_stats'

psql_open A 1

c 'Подключим разделяемые библиотеки.'
c 'Расширение pgpro_pwr получает сводную статистику ожиданий от расширения pg_wait_sampling:'
s 1 "ALTER SYSTEM SET shared_preload_libraries = pgpro_stats;"

c 'Перезагрузим сервер.'
pgctl_restart A

p

###############################################################################
h '2. Запуск транзакции с недостаточной памятью work_mem'

c 'Создадим тестовую базу данных на основе demo:'
psql_open A 1
s 1 "CREATE DATABASE $TOPIC_DB TEMPLATE demo;"

c 'Для удобства настроим путь поиска:'
s 1 "ALTER DATABASE $TOPIC_DB SET search_path TO bookings, public;"

c 'Подключимся к базе данных.'
s 1 "\c $TOPIC_DB"

c 'Подключим расширение:'
s 1 'CREATE EXTENSION pgpro_stats;'

c 'Запустим транзакцию.'
s 1 "BEGIN;"
s 1 "SET LOCAL work_mem = '12MB';"
s 1 "SET LOCAL hash_mem_multiplier = 1;"
s 1 "EXPLAIN (analyze, buffers, costs off, timing off, summary off)
SELECT * FROM bookings b
  JOIN tickets t ON b.book_ref = t.book_ref;"
s 1 "COMMIT;"

###############################################################################
h '3. Отчет по нагрузке'

c 'Соединение хешированием при недостатке work_memory выполняется в двухпроходном режиме и использует временные файлы.'
c 'Проверим, что накопилось в статистике.'

s 1 "SELECT query, plan, calls, temp_blks_read, temp_blks_written
FROM pgpro_stats_statements
WHERE query LIKE 'EXPLAIN (analyze, buffers,%' \gx"

c 'По столбцам temp_blks_read и temp_blks_written можно судить об активности использования временных файлов.'

###############################################################################
h '4. Отчет по нагрузке в улучшенных условиях'

c 'Сбросим статистику.'
s 1 "SELECT pgpro_stats_statements_reset();"

c 'Снова запустим транзакцию с увеличенными значениями параметров.'
c 'Теперь соединение хешированием будет однопроходным и не будет использовать временные файлы.'
s 1 "BEGIN;"
s 1 "SET LOCAL work_mem = '48MB';"
s 1 "SET LOCAL hash_mem_multiplier = 3;"
s 1 "EXPLAIN (analyze, buffers, costs off, timing off, summary off)
SELECT * FROM bookings b
  JOIN tickets t ON b.book_ref = t.book_ref;"
s 1 "COMMIT;"

c 'Проверим, что накопилось в статистике.'
s 1 "SELECT query, plan, calls, temp_blks_read, temp_blks_written
FROM pgpro_stats_statements
WHERE query LIKE 'EXPLAIN (analyze, buffers,%' \gx"

c 'Временные файлы не были использованы.'

###############################################################################

stop_here
cleanup
