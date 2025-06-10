#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Отключение автоочистки'

c 'Пока автоочистка запущена.'
s 1 "SELECT pid, backend_start, backend_type
FROM pg_stat_activity
WHERE backend_type = 'autovacuum launcher';"

c 'Выключаем автоочистку и перечитываем настройки конфигурации.'
s 1 'ALTER SYSTEM SET autovacuum = off;'
s 1 'SELECT pg_reload_conf();'

# Дадим время завершиться процессу autovacuum launcher
wait_sql 1 "SELECT count(*)=0 FROM pg_stat_activity WHERE backend_type = 'autovacuum launcher';"

c 'Теперь процесса autovacuum launcher нет.'
s 1 "SELECT pid, backend_start, backend_type 
FROM pg_stat_activity 
WHERE backend_type = 'autovacuum launcher';"

###############################################################################
h '2. База данных, таблица и индекс'

c 'Создаем базу данных, таблицу и индекс:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 'CREATE TABLE t(n numeric);'
s 1 'CREATE INDEX t_n on t(n);'

c 'Вставляем строки:'

s 1 'INSERT INTO t SELECT random() FROM generate_series(1,100_000);'

###############################################################################
h '3. Изменение строк без очистки'

c 'Для удобства записываем запрос, вычисляющий размер таблицы и индекса, в переменную psql:'

s 1 "\set SIZE 'SELECT pg_size_pretty(pg_table_size(''t'')) table_size, pg_size_pretty(pg_indexes_size(''t'')) index_size\\\g (footer=off)'"
s 1 ':SIZE'

s 1 'UPDATE t SET n=n WHERE n < 0.5;'
s 1 ':SIZE'

s 1 'UPDATE t SET n=n WHERE n < 0.5;'
s 1 ':SIZE'

s 1 'UPDATE t SET n=n WHERE n < 0.5;'
s 1 ':SIZE'

c 'Размер таблицы и индекса постоянно растет.'

###############################################################################
h '4. Полная очистка'

s 1 'VACUUM FULL t;'
s 1 ':SIZE'

c 'Размер таблицы практически вернулся к начальному, индекс стал компактнее (построить индекс по большому объему данных эффективнее, чем добавлять эти данные к индексу построчно).'

###############################################################################
h '5. Изменение строк с очисткой'

s 1 'UPDATE t SET n=n WHERE n < 0.5;'
s 1 'VACUUM t;'
s 1 ':SIZE'

s 1 'UPDATE t SET n=n WHERE n < 0.5;'
s 1 'VACUUM t;'
s 1 ':SIZE'

s 1 'UPDATE t SET n=n WHERE n < 0.5;'
s 1 'VACUUM t;'
s 1 ':SIZE'

c 'Размер увеличился один раз и затем стабилизировался.'
c 'Пример показывает, что удаление (и изменение) большого объема данных по возможности следует разделить на несколько транзакций. Это позволит автоматической очистке своевременно удалять ненужные версии строк, что позволит избежать чрезмерного разрастания таблицы.'

###############################################################################
h '6. Восстанавливаем автоочистку'

s 1 'ALTER SYSTEM RESET autovacuum;'
s 1 'SELECT pg_reload_conf();'

###############################################################################
stop_here
cleanup
demo_end
