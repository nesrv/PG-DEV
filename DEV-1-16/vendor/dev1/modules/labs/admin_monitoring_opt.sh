#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Расширение pg_stat_statements'

c 'Расширение собирает статистику планирования и выполнения всех запросов.'

c 'Для работы расширения требуется загрузить одноименный модуль. Для этого имя модуля нужно прописать в параметре shared_preload_libraries и перезагрузить сервер. Изменять этот параметр лучше в файле postgresql.conf, но для целей демонстрации установим параметр с помощью команды ALTER SYSTEM.'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';"

psql_close 1
pgctl_restart A
psql_open A 1

s 1 'CREATE DATABASE admin_monitoring;'
s 1 "\c admin_monitoring"
s 1 "CREATE EXTENSION pg_stat_statements;"

c 'Теперь выполним несколько запросов.'

s 1 'CREATE TABLE t(n numeric);'
s 1 "SELECT format('INSERT INTO t VALUES (%L)', x)
FROM generate_series(1,5) AS x \gexec"
s 1 'DELETE FROM t;'
s 1 "DROP TABLE t;"

c 'Посмотрим на статистику запроса, который выполнялся чаще всего.'
s 1 "SELECT query, calls, total_exec_time
FROM pg_stat_statements
ORDER BY calls DESC LIMIT 1;"

c 'Разделяемая библиотека больше не требуется, восстановим исходное значение параметра:'
s 1 "ALTER SYSTEM RESET shared_preload_libraries;"
psql_close 1
pgctl_restart A

###############################################################################
stop_here
cleanup
demo_end
