#!/bin/bash

. ../lib

init

start_here 5

###############################################################################
h 'Страница в кеше'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Создадим таблицу с одной строкой:'

s 1 "CREATE TABLE test(
  t text
)
WITH (autovacuum_enabled = off);"
s 1 "INSERT INTO test VALUES ('a row');"

c 'Информацию о содержимом буферного кеша и его использовании можно получить с помощью расширения pg_buffercache, включающего в себя одноименное представление и дополнительные функции:'

s 1 "CREATE EXTENSION pg_buffercache;"

c 'Создадим для удобства представление, расшифровывающее некоторые столбцы.'

c 'Условие на базу данных необходимо, так как в буферном кеше содержатся данные всего кластера. Расшифровать мы можем только информацию из той БД, к которой подключены. Глобальные объекты считаются принадлежащими БД с нулевым OID.'

s 1 "CREATE VIEW pg_buffercache_v AS
SELECT bufferid,
       (SELECT c.relname
        FROM   pg_class c
        WHERE  pg_relation_filenode(c.oid) = b.relfilenode
       ) relname,
       CASE relforknumber
         WHEN 0 THEN 'main'
         WHEN 1 THEN 'fsm'
         WHEN 2 THEN 'vm'
       END relfork,
       relblocknumber,
       isdirty,
       usagecount
FROM   pg_buffercache b
WHERE  b.reldatabase IN (
         0, (SELECT oid FROM pg_database WHERE datname = current_database())
       )
AND    b.usagecount IS NOT NULL;"

c 'В буферном кеше уже находятся страницы таблицы; они появились при выполнении вставки:'

s 1 "SELECT * FROM pg_buffercache_v WHERE relname = 'test';"

c 'Команда EXPLAIN с указанием analyze и buffers показывает использование буферного кеша при выполнении запроса:'

s 1 "EXPLAIN (analyze,buffers,costs off,timing off,summary off)
SELECT * FROM test;"

c 'Строка «Buffers: shared hit=1» говорит о том, что страница была найдена в кеше.'

c 'После выполнения запроса счетчик использования увеличился на единицу:'

s 1 "SELECT * FROM pg_buffercache_v WHERE relname = 'test';"

P 8

###############################################################################
h 'Чтение в свободный буфер'

c 'Перезагрузим сервер, чтобы сбросить буферный кеш.'

pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'В кеше есть свободные буферы:'

s 1 "SELECT count(*) FROM pg_buffercache WHERE usagecount IS NULL;"

c 'Выполним запрос к таблице:'

s 1 "EXPLAIN (analyze,buffers,costs off,timing off,summary off)
SELECT * FROM test;"

c 'Строка «Buffers: shared read=1» показывает, что страницу пришлось прочитать с диска. Вот она:'

s 1 "SELECT * FROM pg_buffercache_v WHERE relname = 'test';"

c 'Количество свободных буферов уменьшилось:'

s 1 "SELECT count(*) FROM pg_buffercache WHERE usagecount IS NULL;"

c 'В кеш попала не только прочитанная страница, но и страницы таблиц системного каталога, которые потребовались планировщику.'

P 14

###############################################################################
h 'Настройка размера кеша'

c 'Используя расширение pg_buffercache, можно наблюдать за состоянием кеша под разными углами.'
c 'Кроме информации о том, как представлена в кеше та или иная страница, можно, например, посмотреть распределение буферов по их «популярности».'

s 1 "SELECT usage_count, buffers AS count FROM pg_buffercache_usage_counts();"

c 'Функция pg_buffercache_usage_counts() возвращает набор строк со сводной информацией о состоянии всех общих буферов, агрегированных по возможным значениям счётчика использования.'

c 'Как и представление pg_buffercache, pg_buffercache_usage_counts() не использует блокировки менеджера буферов, поэтому при параллельной работе в базе данных возможна незначительная погрешность результатов функции.'

c 'Посмотрим, какая доля каких таблиц закеширована (и насколько активно используются эти данные):'

s 1 'SELECT c.relname,
  count(*) blocks,
  round( 100.0 * 8192 * count(*) / pg_table_size(c.oid) ) "% of rel",
  round( 100.0 * 8192 * count(*) FILTER (WHERE b.usagecount > 3) / pg_table_size(c.oid) ) "% hot"
FROM pg_buffercache b
  JOIN pg_class c ON pg_relation_filenode(c.oid) = b.relfilenode
WHERE  b.reldatabase IN (
         0, (SELECT oid FROM pg_database WHERE datname = current_database())
       )
AND    b.usagecount is not null
GROUP BY c.relname, c.oid
ORDER BY 2 DESC
LIMIT 10;'

c 'А сводную информацию о буферном кеше нам покажет функция pg_buffercache_summary:'

s 1 "SELECT * FROM pg_buffercache_summary() \gx"

c 'Подобные запросы могут подсказать, насколько активно используется буферный кеш и дать пищу для размышлений о том, стоит ли увеличивать или уменьшать его размер. Надо учитывать, что такие запросы надо повторять несколько раз: цифры будут меняться в определенных пределах, а набор результатов, полученный для всех буферов, в целом может оказаться несогласованным.'

c 'Информацию, подобную той, что возвращают функции pg_buffercache_summary() и pg_buffercache_usage_counts(), можно получить и с помощью представления pg_buffercache, однако использование функций менее затратно, что удобно для использования в системах мониторинга.'

P 17

###############################################################################
h 'Массовое вытеснение'

c 'Для полного чтения таблиц, размер которых превышает четверть буферного кеша, используется буферное кольцо. Размер кеша (в страницах):'

s 1 "SELECT setting FROM pg_settings WHERE name='shared_buffers';"

c 'Добавим строк в таблицу:'

s 1 "INSERT INTO test SELECT repeat('A',1000) FROM generate_series(1,30000);"
s 1 "ANALYZE test;"
s 1 "SELECT relpages FROM pg_class WHERE relname = 'test';"

c 'Перезагрузим сервер, чтобы сбросить буферный кеш.'

pgctl_restart A
psql_open A 1 $TOPIC_DB

c 'Сбросим данные статистики для представления pg_stat_io, с которым мы будем работать далее:'

s 1 "SELECT pg_stat_reset_shared('io');"

c 'Прочитаем данные из таблицы:'

s 1 "EXPLAIN (analyze,buffers,costs off,timing off,summary off)
SELECT * FROM test;"

c 'Были прочитаны все страницы с данными, но сколько буферов кеша ими занято?'

s 1 "SELECT count(*) FROM pg_buffercache_v WHERE relname = 'test';"

c 'В 16-й версии PostgreSQL появилось представление pg_stat_io, которое показывает статистику ввода/вывода с точки зрения СУБД (кеширование на низком уровне в нем не учитывается). Мы сделаем выборку интересующих нас данных: количество чтений (reads), попаданий (hits) в буферный кеш и повторных использований в буферном кольце (reuses).'

# Чорная магия, чтобы статистика долетела до stats collector
sleep 1
s_bare 1 "SELECT 1;" >/dev/null
sleep 1

s 1 "SELECT context, reads, hits, reuses FROM pg_stat_io
WHERE backend_type = 'client backend' AND
      object = 'relation' AND
      context IN ('normal', 'bulkread');"

c 'Строка с контекстом normal показывает данные по операциям чтения-записи, выполняющимся через общую часть буферного кеша, а bulkread — за его пределами (в том числе использующих буферные кольца).'

c 'А теперь страницы будут изменяться и отсоединяться от буферного кольца. Они могут занять значительную часть кеша:'

s 1 "EXPLAIN (analyze,buffers,costs off,timing off,summary off)
UPDATE test SET t = t || '!';"

c 'Сейчас в кеше находятся все или почти все страницы таблицы, количество которых удвоилось из-за появления новых версий строк:'

s 1 "SELECT relfork, count(*) FROM pg_buffercache_v WHERE relname = 'test' GROUP BY relfork;"

s 1 "SELECT context, reads, hits, reuses FROM pg_stat_io
WHERE backend_type = 'client backend' AND
      object = 'relation' AND
      context IN ('normal', 'bulkread');"

c 'Мы видим накопительную статистику всех клиентских процессов (client backend), выполнявших массовое чтение (bulkread) из обычных таблиц (relation). К таким операциям относится последовательное сканирование таблиц с использованием буферного кольца. Измененные буферы отсоединены от кольца и представлены в строке с контекстом normal.'

P 19

###############################################################################
h 'Временные таблицы'

c 'Создадим временную таблицу с одной строкой:'

s 1 "CREATE TEMP TABLE test_tmp(
  t text
);"

s 1 "INSERT INTO test_tmp VALUES ('a row');"

c 'В плане выполнения запроса обращение к локальному кешу выглядит как «Buffers: local»:'

s 1 "EXPLAIN (analyze,buffers,costs off,timing off,summary off)
SELECT * FROM test_tmp;"

# Снова чорная магия
sleep 1
s_bare 1 "SELECT 1;" >/dev/null
sleep 1

s 1 "SELECT context, hits, extends FROM pg_stat_io
WHERE backend_type = 'client backend' AND
      object = 'temp relation' AND context = 'normal';"

c "Видим, что вставка строки привела к расширению таблицы (extends)."

P 21

###############################################################################
h 'Прогрев кеша'

c 'Рассмотрим самый простой сценарий использования расширения для прогрева кеша.'

s 1 'CREATE EXTENSION pg_prewarm;'

c 'В очередной раз перезапустим сервер, чтобы в кеше не было данных таблицы test:'

pgctl_restart A
psql_open A 1 $TOPIC_DB

s 1 "SELECT count(*) FROM pg_buffercache_v WHERE relname = 'test';"

c 'Вызов функции pg_prewarm без дополнительных параметров полностью считывает основной слой указанной таблицы в буферный кеш:'

s 1 "SELECT pg_prewarm('test');"
s 1 "SELECT relfork, count(*) FROM pg_buffercache_v WHERE relname = 'test' GROUP BY relfork;"

###############################################################################

stop_here
cleanup
demo_end
