#!/bin/bash

. ../lib
init

sudo rm -f /tmp/rep.stat

start_here

###############################################################################

h '1. Подготовка СУБД для работы с расширениями pgpro_scheduler и pg_stat_statements'

psql_open A 1

c "Создадим базу данных $TOPIC_DB:"
s 1 "CREATE DATABASE $TOPIC_DB;"

c 'Подключим разделяемые библиотеки:'
s 1 "ALTER SYSTEM SET shared_preload_libraries = pg_stat_statements, pgpro_scheduler;"
s 1 "ALTER SYSTEM SET track_io_timing = 'on';"

c 'Общее ограничение на количество параллельных процессов:'
s 1 "SHOW max_worker_processes;"

c 'Перезапустим СУБД.'
pgctl_restart A
psql_open A 1 $TOPIC_DB

###############################################################################

h '2. Подключение расширений. Запуск планировщика'

c 'Установим расширения:'
s 1 "CREATE EXTENSION pgpro_scheduler;"
s 1 "CREATE EXTENSION pg_stat_statements;"

c 'База данных для нагрузочного тестирования:'
s 1 "ALTER SYSTEM SET schedule.database = '$TOPIC_DB';"

# c 'Максимальное число рабочих процессов для запланированных заданий, которые могут выполняться одновременно:'
# s 1 "ALTER DATABASE $TOPIC_DB SET schedule.max_workers = 3;"
# 
# c 'Ограничение на число рабочих процессов для выполнения разовых заданий:'
# s 1 "ALTER SYSTEM SET schedule.max_parallel_workers = 3;"
# 
c 'Применим изменения конфигурации:'
s 1 "SELECT pg_reload_conf();"

c 'Включим планировщик заданий:'
s 1 "SELECT schedule.enable();"

c 'Состояние процессов планировщика заданий:'
s 1 "SELECT * FROM schedule.status();"

###############################################################################

h '3. Планирование задач'

c 'Создадим таблицу для сохранения выборок статистики:'
s 1 "CREATE TABLE stat_tab (LIKE pg_stat_statements);"
s 1 "ALTER TABLE stat_tab
  ADD COLUMN time timestamp with time zone DEFAULT now();"

c 'Запланируем копирование статистики в таблицу stat_tab раз в 20 секунд, причем периодическое задание должно работать одну минуту:'

s 1 "SELECT schedule.create_job(
  ('{
    \"commands\": \"INSERT INTO stat_tab SELECT * FROM pg_stat_statements ORDER BY calls DESC LIMIT 3;\",
    \"cron\": \"*/20 * * * * *\",
    \"end_date\": \"'||(now()+'1 minute'::interval)||'\"
  }')::jsonb
);"

c 'Через минуту содержимое таблицы нужно скопировать в файл с помощью разового задания.'

e 'sudo rm -f /tmp/rep.stat'

s 1 "SELECT schedule.submit_job(
  'COPY stat_tab TO ''/tmp/rep.stat''',
  run_after => now() + interval '1 minutes'
);"

c 'Подождем минуту...'

# чуть дольше, чтобы задание выполнилось
wait_status 'sudo test -f /tmp/rep.stat' 0 66

c 'Проверим выполненные задания:'
s 1 "SELECT cron, scheduled_at, started, status, message
FROM schedule.get_log();"

c 'В таблице собраны сведения о наиболее частых запросах:'
s 1 "SELECT time, queryid, calls FROM stat_tab;"

c 'Разовое задание скопировало таблицу в файл:'
e 'sudo ls -l /tmp/rep.stat'

###############################################################################

stop_here
cleanup
