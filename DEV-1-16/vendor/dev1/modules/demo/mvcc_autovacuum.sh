#!/bin/bash

. ../lib

init

start_here 11

###############################################################################
h 'Автоочистка'

c 'Создадим таблицу с 1000 строками:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE TABLE tvac(
  id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  n numeric
);"
s 1 "INSERT INTO tvac(n) SELECT 1 FROM generate_series(1,1000);"

c 'Выставим настройки автоочистки.'
c 'Небольшое время ожидания, чтобы сразу видеть результат:'

s 1 "ALTER SYSTEM SET autovacuum_naptime = 1;"

c 'Один процент строк:'

s 1 "ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.01;"

c 'Нулевой порог:'

s 1 "ALTER SYSTEM SET autovacuum_vacuum_threshold = 0;"

c 'Выставим настройки автоанализа.'
c 'Два процента строк:'

s 1 "ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.02;"

c 'Нулевой порог:'

s 1 "ALTER SYSTEM SET autovacuum_analyze_threshold = 0;"

c 'Перечитаем настройки:'

s 1 "SELECT pg_reload_conf();"

c 'И подождем немного, чтобы сработал автоанализ.'

# Чорная магия, чтобы статистика долетела до stats collector
# (пока число строк таблицы не обновится (сейчас 0), автоочистка не придет)
sleep 1
s_bare 1 "SELECT 1;" >/dev/null
sleep 3

p

c 'Создадим представление, показывающее, нуждается ли наша таблица в очистке. Здесь мы учитываем только мертвые версии, но аналогично можно добавить и условие для вставленных строк.'

s 1 "CREATE VIEW vacuum_v AS
WITH params AS (
  SELECT (SELECT setting::integer
          FROM   pg_settings
          WHERE  name = 'autovacuum_vacuum_threshold') AS vacuum_threshold,
         (SELECT setting::float
          FROM   pg_settings
          WHERE  name = 'autovacuum_vacuum_scale_factor') AS vacuum_scale_factor
)
SELECT st.relname,
       st.n_dead_tup dead_tup,
       (p.vacuum_threshold + p.vacuum_scale_factor*c.reltuples)::integer max_dead_tup,
       st.n_dead_tup > (p.vacuum_threshold + p.vacuum_scale_factor*c.reltuples)::integer need_vacuum,
       st.last_autovacuum
FROM   pg_stat_all_tables st,
       pg_class c,
       params p
WHERE  c.oid = st.relid
AND    c.relname = 'tvac';"

c 'Сейчас таблица не требует очистки (в ней нет ненужных версий) и она ни разу не очищалась:'

s 1 "SELECT * FROM vacuum_v;"

c 'Можно создать аналогичное представление и для анализа:'

s 1 "CREATE VIEW analyze_v AS
WITH params AS (
  SELECT (SELECT setting::integer
          FROM   pg_settings
          WHERE  name = 'autovacuum_analyze_threshold') as analyze_threshold,
         (SELECT setting::float
          FROM   pg_settings
          WHERE  name = 'autovacuum_analyze_scale_factor') as analyze_scale_factor
)
SELECT st.relname,
       st.n_mod_since_analyze mod_tup,
       (p.analyze_threshold + p.analyze_scale_factor*c.reltuples)::integer max_mod_tup,
       st.n_mod_since_analyze > (p.analyze_threshold + p.analyze_scale_factor*c.reltuples)::integer need_analyze,
       st.last_autoanalyze
FROM   pg_stat_all_tables st,
       pg_class c,
       params p
WHERE  c.oid = st.relid
AND    c.relname = 'tvac';"

c 'Представление показывает, что таблица не требует анализа; автоанализ уже был выполнен:'

s 1 "SELECT * FROM analyze_v;"

c 'Отключим автоочистку на уровне таблицы и изменим 11 строк (больше 1%):'

s 1 "ALTER TABLE tvac SET (autovacuum_enabled = off);"

s 1 "UPDATE tvac SET n = n + 1 WHERE id <= 11;"

# Чорная магия, чтобы статистика долетела до stats collector
sleep 1
s_bare 1 "SELECT 1;" >/dev/null
sleep 1

p

c 'Проверим представления:'

s 1 "SELECT * FROM vacuum_v;"
s 1 "SELECT * FROM analyze_v;"

c 'Как видно, таблице требуется автоочистка.'

p

c 'Включим автоочистку для таблицы и подождем несколько секунд...'

s 1 "ALTER TABLE tvac SET (autovacuum_enabled = on);"
sleep 3
# А тут чорной магии не требуется - статистика уже прилетела

p

s 1 "SELECT * FROM vacuum_v;"
s 1 "SELECT * FROM analyze_v;"

c 'Автоочистка пришла и обработала таблицу. Число ненужных версий снова равно нулю. При этом автоанализ не выполнялся.'

p

c 'Изменим еще 11 строк:'

s 1 "ALTER TABLE tvac SET (autovacuum_enabled = off);"
s 1 "UPDATE tvac SET n = n + 1 WHERE id <= 11;"

# Чорная магия, чтобы статистика долетела до stats collector
sleep 1
s_bare 1 "SELECT 1;" >/dev/null
sleep 1

p

s 1 "SELECT * FROM vacuum_v;"
s 1 "SELECT * FROM analyze_v;"

c 'Теперь должна отработать и автоочистка, и автоанализ.'
c 'Проверим это.'

s 1 "ALTER TABLE tvac SET (autovacuum_enabled = on);"

c 'Несколько секунд ожидания...'
sleep 3
# А тут чорной магии не требуется - статистика уже прилетела

p

s 1 "SELECT * FROM vacuum_v;"
s 1 "SELECT * FROM analyze_v;"

c 'Все правильно, отработали оба процесса.'

p

c 'Показанные представления можно использовать для мониторинга очереди таблиц, ожидающих очистку и анализ, убрав условие на имя таблицы. Для полноты картины в них требуется учесть параметры хранения на уровне отдельных таблиц.'

s 1 "ALTER TABLE tvac SET (autovacuum_vacuum_scale_factor = 0.01);"
s 1 "SELECT unnest(reloptions) FROM pg_class WHERE relname = 'tvac';"

###############################################################################

stop_here
cleanup
demo_end
