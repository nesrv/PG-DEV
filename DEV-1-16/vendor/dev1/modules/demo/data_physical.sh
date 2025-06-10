#!/bin/bash

. ../lib

init

start_here 5

###############################################################################
h 'Использование табличных пространств'

c 'Изначально в кластере присутствуют два табличных пространства. Информация о них содержится в системном каталоге:'

s 1 'SELECT spcname FROM pg_tablespace;'

c 'Конечно, это одна из глобальных для всего кластера таблиц.'

c 'Аналогичная команда psql:'

s 1 '\db'

c 'Для нового табличного пространства нужен пустой каталог, владельцем которого является пользователь ОС, запускающий сервер СУБД:'

s 1 "\! sudo mkdir $H/ts_dir"

c 'Сменим владельца каталога:'

s 1 "\! sudo chown postgres $H/ts_dir"

c 'Теперь можем выполнить команду создания табличного пространства:'

s 1 "CREATE TABLESPACE ts LOCATION '$H/ts_dir';"

s 1 '\db'

c 'При создании базы данных можно указать табличное пространство по умолчанию:'

s 1 "CREATE DATABASE $TOPIC_DB TABLESPACE ts;"
s 1 "\c $TOPIC_DB"

c 'Это означает, что все объекты базы по умолчанию будут создаваться в этом табличном пространстве.'

s 1 'CREATE TABLE t(id integer PRIMARY KEY, s text);'
s 1 "INSERT INTO t(id, s)
    SELECT id, id::text FROM generate_series(1,100_000) id;"

P 7

###############################################################################
h 'Слои и файлы'

c 'Очистка обеспечит нам создание всех слоев таблицы:'

s 1 'VACUUM t;'

c 'Узнать расположение файлов, из которых состоит объект, можно так:'

s 1 "SELECT pg_relation_filepath('t');"

c 'Посмотрим на сами файлы (имя и размер в байтах):'

export FPATH=`psql -A -t -X -d $TOPIC_DB -c "SELECT pg_relation_filepath('t');"`
export BASENAME=`basename $PGDATA/$FPATH`
export DIRNAME=`dirname $PGDATA/$FPATH`

e "sudo bash -c 'cd $DIRNAME; ls -l $BASENAME*'"

c 'Видно, что они относятся к трем слоям: основному, fsm и vm.'

c 'Объекты можно перемещать между табличными пространствами, но (в отличие от схем) это приводит к физическому перемещению данных:'

s 1 'ALTER TABLE t SET TABLESPACE pg_default;'
s 1 "SELECT pg_relation_filepath('t');"

p

###############################################################################
h 'Размер объектов'

c 'Узнать размер, занимаемый базой данных и объектами в ней, можно с помощью ряда функций.'

s 1 "SELECT pg_database_size('$TOPIC_DB');"

c 'Для упрощения восприятия можно вывести число в отформатированном виде:'

s 1 "SELECT pg_size_pretty(pg_database_size('$TOPIC_DB'));"

c 'Полный размер таблицы (вместе со всеми индексами):'

s 1 "SELECT pg_size_pretty(pg_total_relation_size('t'));"

c 'А также отдельно размер таблицы...'

s 1 "SELECT pg_size_pretty(pg_table_size('t'));"

c '...и индексов:'

s 1 "SELECT pg_size_pretty(pg_indexes_size('t'));"

c 'При желании можно узнать и размер отдельных слоев таблицы, например:'

s 1 "SELECT pg_size_pretty(pg_relation_size('t','main'));"

c 'Объем, который занимает на диске табличное пространство, показывает другая функция:'

s 1 "SELECT pg_size_pretty(pg_tablespace_size('ts'));"

P 9

###############################################################################
h 'TOAST'

c 'Добавим в таблицу очень длинную строку:'

s 1 "INSERT INTO t(id, s)
SELECT 0, string_agg(id::text,'.') FROM generate_series(1,5000) AS id;"

c 'Изменится ли размер таблицы?'

s 1 "SELECT pg_size_pretty(pg_table_size('t'));"

c 'Да. А размер основного слоя, в котором хранятся данные?'

s 1 "SELECT pg_size_pretty(pg_relation_size('t','main'));"

c 'Нет.'
c 'Поскольку версия строки не помещается в одну страницу, значение атрибута s будет разрезано на части и помещено в отдельную toast-таблицу. Ее можно отыскать в системном каталоге (мы используем тип regclass, чтобы преобразовать oid в имя отношения):'

s 1 "SELECT oid, reltoastrelid::regclass::text FROM pg_class WHERE relname='t';"
export TOAST=`psql -A -t -X -d $TOPIC_DB -c "SELECT reltoastrelid::regclass::text FROM pg_class WHERE relname='t';"`

c 'Символьная строка хранится по частям, из которых PostgreSQL при необходимости склеивает полное значение:'

s 1 "SELECT chunk_id, chunk_seq, left(chunk_data::text,45) AS chuck_data
FROM $TOAST;"

p

c 'В заключение удалим базу данных.'

s 1 '\c postgres'
s 1 "DROP DATABASE $TOPIC_DB;"

c 'После того, как в табличном пространстве не осталось объектов, можно удалить и его:'

s 1 'DROP TABLESPACE ts;'

s 1 "\! sudo rmdir $H/ts_dir"

###############################################################################

stop_here
cleanup
demo_end
