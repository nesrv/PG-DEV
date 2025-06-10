#!/bin/bash

. ../lib
init

start_here 7

###############################################################################
h 'Настройка табличного пространства'

c 'Убедимся, что сжатие поддерживается:'
s 1 "SELECT cfs_version();"

c 'Создадим табличное пространство со сжатием.'

e "sudo mkdir $H/ts_dir"
e "sudo chown postgres: $H/ts_dir"

s 1 "CREATE TABLESPACE cts LOCATION '$H/ts_dir' WITH (compression=on);"
s 1 "\db+ cts"

########################################################################
P 10
h 'Сжатая таблица'

c "В новой базе данных таблицы и индексы будут по умолчанию располагаться в сжатом табличном пространстве."

s 1 "CREATE DATABASE $TOPIC_DB TABLESPACE cts;"
s 1 "\c $TOPIC_DB"

c 'Создадим таблицу с минимальным fillfactor, отключив автоочистку:'

s 1 "CREATE TABLE test (s CHAR(500))
WITH (fillfactor=10, autovacuum_enabled=off);"

c 'Вставим 100000 строк со случайной буквой, в этом случае версии строк будут достаточно короткими и не попадут в TOAST-хранилище:'

s 1 "INSERT INTO test
SELECT chr(ascii('a') + (random()*25)::int) s
FROM generate_series(1,100000);"
s 1 "ANALYZE;"
wait_sql 1 "SELECT reltuples>0 FROM pg_class WHERE relname='test';"

c 'Сколько места в оперативной памяти занимает основной слой таблицы?'

s 1 "SELECT reltuples, relpages,
  pg_size_pretty(relpages * 8192::numeric)
FROM pg_class
WHERE relname='test';
"

c 'А сколько на диске? Чтобы измерение было корректным, предварительно выполним контрольную точку.'

s 1 "CHECKPOINT;"
s 1 "SELECT pg_size_pretty(pg_relation_size('test','main'));"

c 'Прогнозируемая (по первым 10 страницам) и фактическая степени сжатия:'

s 1 "SELECT cfs_estimate('test'), cfs_compression_ratio('test');"

c 'Как видим, наша таблица сжалась в десятки раз.'

p

c 'Системный каталог тоже находится в пространстве по умолчанию (cts), но системные таблицы никогда не сжимаются.'

s 1 "SELECT relname, reltablespace, relpages * 8192 buffers,
  pg_relation_size(oid,'main') file
FROM pg_class
WHERE relname = 'pg_class';"

########################################################################
P 15
h 'Сбор мусора'

c "Сейчас таблица немного фрагментирована:"

s 1 "SELECT pg_size_pretty(pg_table_size('test')), cfs_fragmentation('test');"

c "Посмотрим, что будет, если отключить сбор мусора."

s 1 "ALTER SYSTEM SET cfs_gc = off;"
s 1 "SELECT pg_reload_conf();"

c "Изменим все строки таблицы."

s 1 "UPDATE test SET s = s;"
s 1 "CHECKPOINT;"
s 1 "SELECT pg_size_pretty(pg_table_size('test')), cfs_fragmentation('test');"

c "Объем хранения вырос вдвое, фрагментация около 50%."
p

c "При дальнейшем изменении таблицы рост продолжится."

s 1 "UPDATE test SET s = s;"
s 1 "CHECKPOINT;"
s 1 "SELECT pg_size_pretty(pg_table_size('test')), cfs_fragmentation('test');"
s 1 "UPDATE test SET s = s;"
s 1 "CHECKPOINT;"
s 1 "SELECT pg_size_pretty(pg_table_size('test')), cfs_fragmentation('test');"
s 1 "UPDATE test SET s = s;"
s 1 "CHECKPOINT;"
s 1 "SELECT pg_size_pretty(pg_table_size('test')), cfs_fragmentation('test');"

c "Поэтому в реальной системе мусор необходимо собирать."
p

c "Попробуем собрать мусор в таблице вручную, задав минимальный порог на уровне сеанса, чтобы были обработаны все сегменты:"

s 1 "SET cfs_gc_threshold = 0;"

s 1 "SELECT cfs_gc_relation('test');"

c "Неиспользуемые страницы удалены, размер файла уменьшился:"
s 1 "SELECT pg_size_pretty(pg_table_size('test')), cfs_fragmentation('test');"

c "Обновим таблицу и выполним контрольную точку, чтобы сжатые страницы записались в файл."

s 1 "UPDATE test SET s = s;"
s 1 "CHECKPOINT;"
s 1 "SELECT pg_size_pretty(pg_table_size('test')), cfs_fragmentation('test');"

c " Объем опять вырос вдвое, фрагментация около 50%."

p

c "Теперь вернем автоматический сбор мусора и сбросим порог, который мы задавали на уровне сеанса."
s 1 "ALTER SYSTEM RESET cfs_gc;"
s 1 "SELECT pg_reload_conf();"
s 1 "RESET cfs_gc_threshold; SHOW cfs_gc_threshold;"

c "Если еще раз изменить все строки таблицы, доля мусора превысит порог по умолчанию (50%)."
s 1 "UPDATE test SET s = s;"

s 1 "CHECKPOINT;"

c "Сбор мусора выполнится автоматически (немного подождем)."
# Ждем начала сбора мусора
wait_sql 1 "SELECT cfs_fragmentation('test') < 0.5;"
# А теперь ждем когда за 2 секунды фрагментация не изменится
wait_sql 1 "WITH f AS (SELECT cfs_fragmentation('test') f1,pg_sleep(2),cfs_fragmentation('test') f2) SELECT f.f2=f.f1 FROM f;"

s 1 "SELECT pg_size_pretty(pg_table_size('test')), cfs_fragmentation('test');"

########################################################################

stop_here
cleanup
demo_end
