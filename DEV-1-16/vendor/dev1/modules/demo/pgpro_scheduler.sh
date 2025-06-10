#!/bin/bash

. ../lib
init

start_here 5

###############################################################################
h 'Установка расширения pgpro_scheduler'

c 'Создадим базу данных:'
s 1 "CREATE DATABASE $TOPIC_DB;"

c 'Для работы расширения необходимо подключить библиотеку:'
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pgpro_scheduler';"

c 'Общее ограничение на количество фоновых рабочих процессов в системе, значения по умолчанию достаточно для работы с одной базой:'
s 1 "SHOW max_worker_processes;"

c 'Подключение библиотеки требует перезапуска СУБД.'
pgctl_restart A
psql_open A 1

c 'Установим расширение pgpro_scheduler в базе данных, в которой оно будет использоваться.'

s 1 "\c $TOPIC_DB"
s 1 "CREATE EXTENSION pgpro_scheduler;"

c 'Объекты расширения находятся в схеме schedule. Например, представления для мониторинга разовых заданий:'
s 1 "\dv schedule.*"

p
###############################################################################
h 'Настройка'

c 'Укажем имена баз данных, для которых будут запускаться задания:'
s 1 "ALTER SYSTEM SET schedule.database = '$TOPIC_DB';"

c 'Применим изменение конфигурации.'
s 1 "SELECT pg_reload_conf();"

c 'Установим ограничения на уровне базы данных.'
c 'Максимальное число рабочих процессов для периодических заданий:'
s 1 "ALTER DATABASE $TOPIC_DB SET schedule.max_workers = 3;"

c 'Ограничение на число рабочих процессов, выполняющих разовые задания:'
s 1 "ALTER DATABASE $TOPIC_DB SET schedule.max_parallel_workers = 3;"

c 'Включим планировщик заданий:'
s 1 "SELECT schedule.enable();"

c 'Состояние процессов планировщика заданий:'
s 1 "SELECT * FROM schedule.status();"

c 'Информация об этих процессах доступна и в pg_stat_activity:'
s 1 "SELECT pid, datname, application_name, backend_type, query
FROM pg_stat_activity
WHERE application_name ~ '^pgp-s';"

P 8
###############################################################################
h 'Планирование заданий'

c 'Создадим таблицу:'
s 1 "CREATE TABLE t (
  bknd int DEFAULT pg_backend_pid(),
  txid bigint DEFAULT txid_current(),
  ttime timestamptz DEFAULT now()
);"

c 'А теперь создадим периодическое задание, используя формат crontab. Формат использует пять полей для идентификации времени:'

ul 'минуты часа (0-59);'
ul 'часы (0-23);'
ul 'дни месяца (1-31);'
ul 'месяц (1-12 или трехбуквенное сокращение);'
ul 'дни недели (0 — воскресенье ... 6 — суббота, или трехбуквенные сокращения).'

p

c 'Если в поле после звездочки через косую черту указано число — это шаг выполнения. Например,'
c '*/10 * * * *'
c 'означает «раз в десять минут».'
c 'Расширенный формат cron использует шесть полей с секундами. Например,'
c '*/30 * * * * *'
c 'означает «раз в тридцать секунд».'

p

c 'Запланируем задание на выполнение раз в минуту:'

s 1 "SELECT schedule.create_job(
  '{ \"commands\": \"INSERT INTO t DEFAULT VALUES\",
     \"cron\": \"*/1 * * * *\" }'
);"

c 'Получим информацию о запланированном задании:'

s 1 "SELECT id, commands, run_as, active
FROM schedule.get_cron();"

c 'Функция get_job информирует о задании, возвращая значение типа cron_rec.'
c 'Проверим поле rule, описывающее расписание, преобразовав расписание из представления JSONB в текстовые строки и урезав их по ширине:'

s 1 "SELECT substring(jsonb_each_text(rule)::text FOR 90) AS rule 
FROM schedule.get_job(1);"

c 'Через минуту сработает первое задание. Подождем...'

wait_sql 1 'SELECT count(*) > 0 FROM t;' 80

c 'Проверим, что было добавлено в таблицу t:'

s 1 "SELECT * FROM t;"

c 'Функция timetable информирует о выполненных и запланированных заданиях. Получим список заданий за 5 минут:'

s 1 "SELECT id, type, commands, scheduled_at, status 
FROM schedule.timetable(
  now() - interval '3 minutes',
  now() + interval '2 minutes'
)
ORDER BY scheduled_at;"

c 'Отчет о выполненных заданиях планировщика:'

s 1 "SELECT cron, scheduled_at, started, status, message
FROM schedule.get_log();"

p 
###############################################################################
h 'Управление запланированными заданиями'

c 'До сих пор задание выполнялось в ноль секунд каждой минуты:'

s 1 "SELECT jsonb_array_elements(rule->'seconds') FROM schedule.get_job(1);"

c 'Пусть задание выполняется чаще — раз в десять секунд.'
c 'Используем расширенный формат cron из шести полей, где первое поле — секунды:'

s 1 "SELECT schedule.set_job_attribute(1, 'cron','*/10 * * * * *');"

c 'Проверим в rule: задание должно быть запланировано для исполнения с периодичностью раз в десять секунд.'

s 1 "SELECT jsonb_array_elements(rule->'seconds') FROM schedule.get_job(1);"

c 'Подождем немного...'

sleep 2
sleep-ni 9 # в интерактивном режиме и так будет пауза, а в неинтерактивном подождем подольше

c 'Проверим, что было добавлено в таблицу t:'
s 1 "SELECT * FROM t;"

c 'Временно приостановим задание. Новые записи не будут попадать в таблицу.'
s 1 "SELECT schedule.deactivate_job(1);"

c 'Проверим состояние задания — оно должно быть не активно:'
s 1 "SELECT id, commands, run_as, active FROM schedule.get_job(1);"

c 'Подождем немного...'
sleep 2
sleep-ni 18 # в интерактивном режиме и так будет пауза, а в неинтерактивном подождем подольше

c 'Снова запустим задание и проверим состояние:'
s 1 "SELECT schedule.activate_job(1);"
s 1 "SELECT id, commands, run_as, active FROM schedule.get_job(1);"

c 'Подождем еще немного...'
sleep 10
sleep-ni 10

c 'Проверим записи в таблице t:'
s 1 "SELECT * FROM t;"

c 'Выполненные задания отображаются в журнале:'
s 1 "SELECT cron, scheduled_at, started, status, message
FROM schedule.get_log() WHERE cron = 1;"

c 'Снова приостановим задание и очистим таблицу.'
s 1 "SELECT schedule.deactivate_job(1);"
s 1 "DELETE FROM t;"

p
###############################################################################
h 'Команды в отдельных транзакциях'

c 'В атрибуте commands значения могут задаваться в виде текста или массива.'
c 'Если отдельные команды SQL заданы текстовой строкой через точку с запятой, то все команды задания будут выполнены в одной транзакции.'
c 'Если команды SQL заданы JSON-массивом, то каждая из них будет выполнена в отдельной транзакции.'

c 'Создадим планируемое задание для заполнения этой таблицы раз в десять секунд.'
c 'Каждая SQL-команда выполняется в отдельной транзакции. Значения now() для каждой транзакции — свои, как и идентификаторы транзакции.'
s 1 "SELECT schedule.create_job(
  '{ \"commands\": [
       \"INSERT INTO t DEFAULT VALUES\", 
       \"SELECT pg_sleep(5)\", 
       \"INSERT INTO t DEFAULT VALUES\"
     ],
     \"cron\": \"*/10 * * * * *\" }'
);"

c 'Снова немного подождем... '
wait_sql 1 'SELECT count(*) > 1 FROM t;' 80
s 1 "SELECT schedule.drop_job(2);"

c 'Проверим, что было добавлено в таблицу:'
s 1 "SELECT * FROM t;"
c 'Команды были выполнены одним обслуживающим процессом, но в отдельных транзакциях.'

p
###############################################################################
h 'Команды в одной транзакции'

c 'Даже если команды заданы массивом, можно задать атрибуту use_same_transaction значение true, и все команды будут выполнены в одной транзакции.'

c 'Удалим все записи в таблице.'
s 1 "DELETE FROM t;"

c 'В одной транзакции значения времени, которые возвращает функция now(), будут одинаковыми.'
s 1 "SELECT schedule.create_job(
  '{ \"commands\": [
       \"INSERT INTO t DEFAULT VALUES\", 
       \"SELECT pg_sleep(5)\", 
       \"INSERT INTO t DEFAULT VALUES\"
     ],
     \"cron\": \"*/10 * * * * *\",
     \"use_same_transaction\": true}'
);"

c 'Подождем чуть-чуть... '
wait_sql 1 'SELECT count(*) > 0 FROM t;' 80

c 'Удалим задание и проверим, что было добавлено в таблицу.'
s 1 "SELECT schedule.drop_job(3);"
s 1 "SELECT * FROM t;"
c 'Все три оператора задания выполнились в одной транзакции.'

c 'Снова очистим таблицу и запустим первое задание.'
s 1 "DELETE FROM t;"
s 1 "SELECT schedule.activate_job(1);"

P 10
###############################################################################
h 'Разовые задания'

c 'Запланируем разовое задание, удаляющее через десять секунд таблицу t:'
s 1 "SELECT schedule.submit_job(
  'DROP TABLE t',
  run_after := now() + interval '10 seconds'
);"

c 'Таблица t пока на месте:'
si 1 "SELECT * FROM t;"

c 'Подождем немного...'
wait_sql 1 "SELECT count(*) = 0 FROM pg_class WHERE relname='t';" 20
s 1 "SELECT * FROM t;"
c 'Таблица уже удалена.'

c 'В таблице заданий выводится информация и о разовых заданиях:'
s 1 "SELECT id, type, commands, scheduled_at, status
FROM schedule.timetable(
  now() - interval '1 minutes',
  now()
)
WHERE id = 1
ORDER BY scheduled_at;"

c 'Свойство onrollback периодического задания задает действия при сбое команды задания — будем восстанавливать таблицу, предполагая ее отсутствие:'
#_ s 1 "SELECT schedule.set_job_attribute(1, 'onrollback', 
#_   'CREATE TABLE IF NOT EXISTS t (time timestamptz)'
#_ );"

s 1 "SELECT schedule.set_job_attribute(1, 'onrollback', 
  'CREATE TABLE t (
     bknd int DEFAULT pg_backend_pid(),
     txid bigint DEFAULT txid_current(),
     ttime timestamptz DEFAULT now()
   )'
);"

c 'Проверим состояние задания:'
s 1 "SELECT id, commands, run_as, active
FROM schedule.get_job(1);"

c 'Подождем еще немного...'
wait_sql 1 "SELECT count(*) > 0 FROM pg_class WHERE relname='t';" 20

c 'Теперь таблица восстановлена и пока пуста:'
interactive_save=$interactive
interactive=false
s 1 "SELECT * FROM t;"
interactive=$interactive_save

c 'Подождем еще...'
wait_sql 1 "SELECT count(*) > 0 FROM t;" 20

c 'Теперь таблица уже не пуста:'
s 1 "SELECT * FROM t;"

c 'Посмотрим записи отчета:'
s 1 "SELECT cron, scheduled_at, commands, started, status, message
FROM schedule.get_log()
WHERE cron = 1;"

c 'Удалим запланированное задание:'
s 1 "SELECT schedule.drop_job(1);"

###############################################################################

stop_here
cleanup
demo_end
