#!/bin/bash

. ../lib

init

start_here ...

###############################################################################
h '1. Прогрев кеша с помощью pg_prewarm'

c 'Расширение необходимо добавить в загружаемые библиотеки и перезапустить сервер:'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_prewarm';"
pgctl_restart A

c 'Создадим таблицу с данными:'

psql_open A 1
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE TABLE t(n integer);"
s 1 "INSERT INTO t(n) SELECT id FROM generate_series(1,10_000) id;"

c 'Проверим наличие страниц в буферном кеше:'

s 1 "CREATE EXTENSION pg_buffercache;"

s 1 "SELECT count(*)
FROM pg_buffercache
WHERE relfilenode = pg_relation_filenode('t'::regclass);"

c 'Перезапустим сервер.'

pgctl_restart A

c 'Проверим буферный кеш:'

psql_open A 1 $TOPIC_DB
s 1 "SELECT count(*)
FROM pg_buffercache
WHERE relfilenode = pg_relation_filenode('t'::regclass);"

c 'Все страницы были автоматически загружены в буферный кеш при старте сервера.'

c 'Отключим расширение.'

s 1 "ALTER SYSTEM RESET shared_preload_libraries;"
pgctl_restart A

###############################################################################
h '2. Массовое вытеснение'

psql_open A 1 $TOPIC_DB

c 'Размер буферного кеша:'

s 1 "SHOW shared_buffers;"

c 'В созданной таблице 10 тысяч строк занимают:'

s 1 "SELECT pg_size_pretty(pg_table_size('t'));"

c 'Добавим еще строк так, чтобы увеличить размер таблицы примерно до половины буферного кеша:'

s 1 "INSERT INTO t(n) SELECT id FROM generate_series(1,2_000_000) id;"

s 1 "SELECT pg_size_pretty(pg_table_size('t')),
          pg_table_size('t')/8192 AS pages;"

c 'Перезагрузим сервер.'

pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'Выполним запрос, читающий все табличные страницы:'

s 1 "SELECT count(*) FROM t;"

c 'В буферном кеше данные таблицы занимают всего:'

s 1 "SELECT count(*)
FROM pg_buffercache
WHERE relfilenode = pg_relation_filenode('t'::regclass);"

c 'Это работает механизм, защищающий буферный кеш от массового вытеснения «одноразовыми» данными, которые вряд ли понадобятся снова. Он действует при полном сканировании больших таблиц, очистке и т. п. Такие операции используют только небольшую часть кеша (так называемое буферное кольцо).'

###############################################################################
h '3. Зависимость производительности от режима фиксации'

c 'Инициализируем тестовые таблицы:'

e "pgbench -i $TOPIC_DB"

c 'Синхронная фиксация включена:'

s 1 "SHOW synchronous_commit;"

c 'Запускаем эталонный тест TPC-B на 30 секунд:'

e "pgbench -T 30 $TOPIC_DB"

c 'Показатель — количество транзакций в секунду (tps).'

c 'Выключаем синхронную фиксацию:'

s 1 "ALTER SYSTEM SET synchronous_commit = off;"
s 1 "SELECT pg_reload_conf();"

c 'Повторяем тест:'

e "pgbench -T 30 $TOPIC_DB"

c 'Число транзакций в секунду заметно выше. Ускорение, конечно, зависит от типа нагрузки и характеристик оборудования.'

c 'Восстановим значение параметра по умолчанию:'

s 1 "ALTER SYSTEM RESET synchronous_commit;"
s 1 "SELECT pg_reload_conf();"

###############################################################################

stop_here
cleanup
