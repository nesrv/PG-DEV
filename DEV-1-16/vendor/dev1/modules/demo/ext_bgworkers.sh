#!/bin/bash

. ../lib

init

start_here

c 'Готовим базу данных...'

interactive_save=$interactive
interactive=false
s 1 'CREATE DATABASE ext_fts_overview;'
e 'zcat ~/mail_messages.sql.gz | psql -d ext_fts_overview'
s 1 '\c ext_fts_overview' # sic!
interactive=$interactive_save

start_here 5

###############################################################################
h 'Использование фоновых процессов'

c 'Вот простой наглядный пример использования фоновых процессов для распараллеливания запросов. Если требуется посчитать количество строк в большой таблице, ведущий процесс запускает несколько рабочих процессов (в данном случае 2):'

s 1 "EXPLAIN (analyze, costs off, timing off)
SELECT count(*) FROM mail_messages;"

c 'Запланированное количество и число реально запущенных процессов могут отличаться, если на момент запуска запроса пул фоновых процессов будет исчерпан.'

c 'В конце частичные результаты собираются и агрегируются лидирующим процессом чтобы получить итоговое значение.'

P 8

###############################################################################
h 'Расширение dblink'

c 'Это стандартное расширение. Установим его:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE EXTENSION dblink;"

c 'Ниже — самый простой способ выполнить одиночный запрос на удаленном сервере. Первый параметр функции — строка соединения, второй — команда, которую надо выполнить.'

c 'Функция возвращает множество строк типа record, поэтому структуру составного типа необходимо указывать явно при ее вызове.'

s 1 "SELECT * FROM dblink(
    'host=localhost port=5432 dbname=postgres user=postgres password=postgres',
    \$\$ SELECT * FROM generate_series(1,3); \$\$
) AS (result integer);"

p

c 'Команду, не возвращающую строки, можно выполнить с помощью другой функции:'

s 1 "SELECT * FROM dblink_exec(
    'host=localhost port=5432 dbname=postgres user=postgres password=postgres',
    \$\$ VACUUM; \$\$
);"

p

c 'Обе функции открывают соединение, выполняют команду и тут же закрывают соединение. Но есть возможность явно управлять соединением. Откроем его, указав имя:'

s 1 "SELECT * FROM dblink_connect(
    'remote',
    'host=localhost port=5432 dbname=postgres user=postgres password=postgres'
);"

c 'Можно открыть и несколько соединений. Текущие открытые соединения показывает функция:'

s 1 "SELECT * FROM dblink_get_connections();"

c 'Теперь можно выполнять команды, используя открытое соединение. В том числе можно вручную управлять транзакциями:'

s 1 "SELECT * FROM dblink_exec(
    'remote',
    \$\$ BEGIN; \$\$
);"

s 1 "SELECT * FROM dblink(
    'remote',
    \$\$ SELECT pg_backend_pid(); \$\$
) AS (pid integer);"

s 1 "SELECT * FROM dblink_exec(
    'remote',
    \$\$ COMMIT; \$\$
);"

p

c 'Важная возможность — асинхронные вызовы. Следующая функция отправит запрос на сервер и тут же вернет управление:'

s 1 "SELECT * FROM dblink_send_query(
    'remote',
    \$\$ SELECT 'done' FROM pg_sleep(10); \$\$
);"

ul '1 — успешно;'
ul '0 — ошибка.'

c 'Далее мы можем проверить, выполняется ли еще запрос:'

sleep 3
si 1 "SELECT CASE dblink_is_busy('remote')
    WHEN 1 THEN 'еще выполняется'
    ELSE 'уже выполнился'
END;"

c 'Результат получаем так (если запрос еще не выполнился, функция сама дождется результатов):'

s 1 "SELECT * FROM dblink_get_result(
    'remote'
) AS (result text);"

p

c 'Не забываем закрыть соединение:'

s 1 "SELECT * FROM dblink_disconnect('remote');"

P 10

###############################################################################
h 'Расширение pg_background'

c 'Расширение уже собрано и доступно для установки в виртуальной машине курса:'

s 1 'CREATE EXTENSION pg_background;'

c 'Расширение предоставляет всего три функции.'

c 'Функция pg_background_launch запускает фоновый процесс, выполняющий одну SQL-команду.'

c 'Например, выполним в фоне простой запрос. Для удобства он будет работать 10 секунд:'

s 1 "SELECT pg_background_launch(
    \$\$ SELECT 2+2 FROM (SELECT pg_sleep(10)) \$\$
);"
export PIDBG=`sudo -i -u $OSUSER psql -A -t -X -d postgres -c "SELECT pid FROM pg_stat_activity WHERE backend_type = 'pg_background'"`

c 'Пока запрос выполняется, мы можем увидеть процесс в pg_stat_activity:'

sleep 3
si 1 "SELECT query, backend_type, wait_event_type, wait_event
FROM pg_stat_activity WHERE pid = $PIDBG \gx"

c 'Обратите внимание на ожидание.'

p

c 'Функция pg_background_result выводит результат выполнения фоновой команды (при необходимости дожидаясь ее окончания).'

c 'Функция возвращает значения типа record, поэтому для вывода необходимо конкретизировать названия и типы полей составного типа.'

s 1 "SELECT * FROM pg_background_result($PIDBG) AS (result integer);"

p

c 'Функция pg_background_detach отключает текущий процесс от ожидания результатов фонового процесса.'

c 'Передача результатов выполняется через очередь сообщений в разделяемой памяти сервера. Поэтому при переполнении очереди фоновый процесс будет ждать, пока мы не прочитаем накопившиеся сообщения, даже если они нас не интересуют.'

c 'Запустим процесс, возвращающий много информации:'

s 1 "SELECT pg_background_launch(
    \$\$ SELECT * FROM generate_series(1,1_000_000) \$\$
);"
export PIDBG=`sudo -i -u $OSUSER psql -A -t -X -d postgres -c "SELECT pid FROM pg_stat_activity WHERE backend_type = 'pg_background'"`

sleep 2

s 1 "SELECT query, backend_type, wait_event_type, wait_event
FROM pg_stat_activity WHERE pid = $PIDBG \gx"

c 'Обратите внимание на ожидание.'

c 'Отключимся от процесса:'

s 1 "SELECT * FROM pg_background_detach($PIDBG);"

s 1 "SELECT query, backend_type, wait_event_type, wait_event
FROM pg_stat_activity WHERE pid = $PIDBG \gx"

c 'Больше фоновый процесс ничего не ждет (и, возможно, уже отработал).'

c 'Заметим, что в случае dblink сложностей с переполнением буфера не возникает, потому что используется не межпроцессное взаимодействие, а устанавливается обычное соединение по клиент-серверному протоколу.'

p

c 'Интересно, что изначально в состав расширения pg_background планировалось включить четвертую функция pg_background_run(pid, query), которая должна была передавать новое задание уже запущенному процессу, избегая затрат на создание очередного фонового процесса. Однако пока что это не реализовано.'


###############################################################################

stop_here
cleanup
demo_end
