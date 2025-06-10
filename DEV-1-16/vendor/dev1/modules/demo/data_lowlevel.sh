#!/bin/bash


. ../lib

init

start_here 5

###############################################################################
h 'Расположение файлов'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Создадим таблицу и посмотрим на файлы, принадлежащие ей.'

s 1 "CREATE TABLE t(
  id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY, 
  n numeric
);"

s 1 "INSERT INTO t(n) SELECT id FROM generate_series(1,10_000) AS id;"

c 'Чтобы сформировались дополнительные слои, выполним очистку:'

s 1 "VACUUM t;"

c 'Путь до основного файла относительно PGDATA можно получить функцией:'

s 1 "SELECT pg_relation_filepath('t');"
t_PATH=$(s_bare 1 "SELECT pg_relation_filepath('t');")

c 'Поскольку таблица находится в табличном пространстве pg_default, путь начинается с base. Затем идет имя каталога для базы данных:'

s 1 "SELECT oid FROM pg_database WHERE datname = '$TOPIC_DB';"
dbOID=$(s_bare 1 "SELECT OID FROM pg_database WHERE datname = '$TOPIC_DB';")

c 'Затем — собственно имя файла. Его можно узнать следующим образом:'

s 1 "SELECT relfilenode FROM pg_class WHERE relname = 't';"
export relID=$(s_bare 1 "SELECT relfilenode FROM pg_class WHERE relname = 't';")

c 'Тем и удобна функция pg_relation_filepath, что выдает готовый путь без необходимости выполнять несколько запросов к системному каталогу.'

p

c 'Посмотрим на файлы. Доступ к каталогу PGDATA имеет только пользователь ОС postgres, поэтому команда ls выдается от его имени:'

eu postgres "ls -l $PGDATA_A/$t_PATH*"

c 'Мы видим три слоя: основной слой, карту свободного пространства (fsm) и карту видимости (vm).'

c 'Аналогично можно посмотреть и на файлы индекса:'

s 1 '\d t'
s 1 "SELECT pg_relation_filepath('t_pkey');"
i_PATH=$(s_bare 1 "SELECT pg_relation_filepath('t_pkey');")

eu postgres "ls -l $PGDATA_A/$i_PATH*"

c 'И на файлы последовательности, созданной для первичного ключа:'

s 1 "SELECT pg_relation_filepath(pg_get_serial_sequence('t','id'));"
s_PATH=$(s_bare 1 "SELECT pg_relation_filepath(pg_get_serial_sequence('t','id'));")

eu postgres "ls -l $PGDATA_A/$s_PATH*"

c 'Для индекса карта свободного пространства строится при наличии пустых страниц, а для последовательности существует только основной слой.'

p

c 'Временные таблицы хранятся так же, как и постоянные.'

s 1 "CREATE TEMP TABLE temp AS SELECT * FROM t;"
s 1 "VACUUM temp;"

s 1 "SELECT pg_relation_filepath('temp');"
t_PATH=$(s_bare 1 "SELECT pg_relation_filepath('temp');")

c 'К имени файла добавляется префикс, соответствующий номеру схемы для временных объектов.'

eu postgres "ls -l $PGDATA_A/$t_PATH*"

p

c 'Существует полезное приложение oid2name, входящее в стандартную поставку, с помощью которого можно легко связать объекты БД и файлы.'
c 'Можно посмотреть все базы данных:'

e "${BINPATH_A}oid2name"

c 'Можно посмотреть все объекты в базе:'

e "${BINPATH_A}oid2name -d $TOPIC_DB"

c 'Или все табличные пространства в базе:'

e "${BINPATH_A}oid2name -d $TOPIC_DB -s"

c 'Можно по имени таблицы узнать имя файла:'

e "${BINPATH_A}oid2name -d $TOPIC_DB -t t"

c 'Или наоборот, по номеру файла узнать таблицу:'

e "${BINPATH_A}oid2name -d $TOPIC_DB -f $relID"

p

###############################################################################
h 'Размер слоев'

c 'Размер файлов, входящих в слой, можно, конечно, посмотреть в файловой системе, но существует специальная функция для получения размера каждого слоя в отдельности:'

s 1 "SELECT pg_relation_size('t','main') main,
          pg_relation_size('t','fsm') fsm,
          pg_relation_size('t','vm') vm;"

P 7

###############################################################################
h 'TOAST'

c 'В таблице t есть столбец типа numeric. Этот тип может работать с очень большими числами. Например, с такими:'

s 1 "SELECT length( (123456789::numeric ^ 12345::numeric)::text );"

c 'При этом, если вставить такое значение в таблицу, размер файлов не изменится:'

s 1 "SELECT pg_relation_size('t','main');"
s 1 "INSERT INTO t(n) SELECT 123456789::numeric ^ 12345::numeric;"
s 1 "SELECT pg_relation_size('t','main');"

p

c 'Поскольку версия строки не может поместиться на одну страницу, значение атрибута n хранится в отдельной toast-таблице. Toast-таблица и индекс к ней создаются автоматически для каждой таблицы, в которой есть потенциально «длинный» тип данных, и используются по необходимости.'
c 'Имя и идентификатор такой таблицы можно найти следующим образом:'

s 1 "SELECT relname, relfilenode FROM pg_class WHERE oid = (
    SELECT reltoastrelid FROM pg_class WHERE oid = 't'::regclass
);"

toastRELID=$(s_bare 1 "SELECT relfilenode FROM pg_class WHERE oid = (SELECT reltoastRELID FROM pg_class WHERE relname='t');")

c 'Вот и файлы toast-таблицы:'

eu postgres "ls -l $PGDATA_A/base/$dbOID/$toastRELID*"

p

c 'Существуют несколько стратегий работы с длинными значениями. Название стратегии показывается в поле Storage:'

s 1 "\d+ t"

ul 'plain    — TOAST не применяется (тип имеет фиксированную длину);'
ul 'extended — применяется как сжатие, так и отдельное хранение;'
ul 'external — сжатие не используется, только отдельное хранение;'
ul 'main     — такие поля обрабатываются в последнюю очередь и выносятся в toast-таблицу, только если сжатия недостаточно.'

c 'Стратегия назначается для каждого столбца при создании таблицы. Ее можно указать явно, а значение по умолчанию зависит от типа данных.'

p

c 'При необходимости стратегию можно впоследствии изменить. Например, если известно, что в столбце хранятся уже сжатые данные, разумно поставить стратегию external.'
c 'Просто для примера:'

s 1 "ALTER TABLE t ALTER COLUMN n SET STORAGE external;"

c 'Эта операция не меняет существующие данные в таблице, но определяет стратегию работы с новыми версиями строк.'

P 9

###############################################################################
h 'Размер таблицы'

c 'Размер таблицы, включая toast-таблицу и обслуживающий ее индекс:'
s 1 "SELECT pg_table_size('t');"

c 'Общий размер всех индексов таблицы:'
s 1 "SELECT pg_indexes_size('t');"

c "Для получения размера отдельного индекса можно воспользоваться функцией pg_table_size. Toast-части у индексов нет, поэтому функция покажет только размер всех слоев индекса (main, fsm)."

c 'Сейчас у таблицы есть только индекс по первичному ключу, поэтому размер этого индекса совпадает со значением pg_indexes_size:'

s 1 "SELECT pg_table_size('t_pkey') AS t_pkey;"

c 'Общий размер таблицы, включающий TOAST и все индексы:'
s 1 "SELECT pg_total_relation_size('t');"

###############################################################################
stop_here
cleanup
demo_end
