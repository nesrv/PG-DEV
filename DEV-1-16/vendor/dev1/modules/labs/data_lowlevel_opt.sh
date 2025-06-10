#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Сравнение размеров базы данных и таблиц в ней'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Даже пустая база данных содержит таблицы, относящиеся к системного каталогу. Полный список отношений можно получить из таблицы pg_class. Из выборки надо исключить:'

ul 'таблицы, общие для всего кластера (они не относятся к текущей базе данных);'
ul 'индексы и toast-таблицы (они будут автоматически учтены при подсчета размера).'

s 1 "SELECT sum(pg_total_relation_size(oid))
FROM pg_class
WHERE NOT relisshared -- локальные объекты базы
AND relkind = 'r';  -- обычные таблицы"

c 'Размер базы данных оказывается несколько больше:'

s 1 "SELECT pg_database_size('$TOPIC_DB');"

c 'Дело в том, что функция pg_database_size возвращает размер каталога файловой системы, а в этом каталоге находятся несколько служебных файлов.'

s 1 "SELECT oid FROM pg_database WHERE datname = '$TOPIC_DB';"
v_DBOID=`s_bare 1 "SELECT oid FROM pg_database WHERE datname = '$TOPIC_DB';"`

c 'Обратите внимание, что следующая команда ls выполняется от имени пользователя postgres. Чтобы повторить такую команду, удобно сначала открыть еще одно окно терминала и переключиться в нем на другого пользователя командой:'

e_fake "sudo -i -u postgres"

c 'И затем в этом же окне выполнить:'

eu postgres "ls -l $PGDATA_A/base/$v_DBOID/"'[^0-9]*'

ul 'pg_filenode.map  — отображение oid некоторых таблиц в имена файлов;'
ul 'pg_internal.init — кеш системного каталога;'
ul 'PG_VERSION       — версия PostgreSQL.'

c 'Из-за того, что одни функции работают на уровне объектов базы данных, а другие — на уровне файловой системы, бывает сложно точно сопоставить возвращаемые размеры. Это относится и к функции pg_tablespace_size.'

###############################################################################
h '2. Поддержка методов сжатия TOAST'

c 'Представление pg_config показывает параметры, которые были переданы скрипту configure при сборке PostgreSQL.'
s 1 "SELECT * FROM (
  SELECT string_to_table(setting, ''' ''') AS setting 
  FROM pg_config WHERE name = 'CONFIGURE'
) 
WHERE setting ~ '(lz|zs)';"

c 'Какой метод сжатия TOAST используется по умолчанию?'
s 1 "\dconfig *toast*"

c 'Какие методы можно применять?'
s 1 "SELECT setting, enumvals FROM pg_settings WHERE name = 'default_toast_compression';"

###############################################################################
h '3. Сравнение методов сжатия'

c 'Сравним методы сжатия на примере текстовых данных.'
c 'Чтобы получить текст большого объема, возьмем исполняемый файл postgres и преобразуем его в текст с помощью алгоритма Base 32, который применяется в электронной почте.'
e "sudo cat ${BINPATH_A}postgres | base32 -w0 > /tmp/gram.input"

c 'Получившийся текстовый файл имеет достаточный размер.'
e "ls -l --block-size=K /tmp/gram.input"

c 'Создадим таблицу для загрузки текстовых данных.'
c 'Для столбца txt установим стратегию хранения EXTERNAL, которая допускает отдельное хранение, но не сжатие.'
s 1 "CREATE TABLE t (
  txt text STORAGE EXTERNAL
);"

# прогреваем кеш
DUMMY=`s_bare 1 "COPY t FROM '/tmp/gram.input';"`
DUMMY=`s_bare 1 "TRUNCATE TABLE t;"`

c 'Загрузим данные из текстового файла.'
s 1 "\timing on"
s 1 "COPY t FROM '/tmp/gram.input';"
s 1 "\timing off"

c 'Проверим размер таблицы, включая TOAST.'
s 1 "SELECT pg_table_size('t')/1024;"

c 'Опустошим таблицу и зададим сжатие с помощью pglz.'
s 1 "TRUNCATE TABLE t;"
s 1 "ALTER TABLE t
ALTER COLUMN txt SET STORAGE EXTENDED,
ALTER COLUMN txt SET COMPRESSION pglz;"
c 'Теперь используется стратегия EXTENDED, которая допускает как сжатие, так и отдельное хранение.'

c 'Снова загрузим данные.'
s 1 "\timing on"
s 1 "COPY t FROM '/tmp/gram.input';"
s 1 "\timing off"

s 1 "SELECT pg_table_size('t')/1024;"
c 'Размер таблицы значительно уменьшился, но при этом заметно выросло время загрузки.'

c 'Снова опустошим таблицу и зададим теперь сжатие с помощью lz4.'
s 1 "TRUNCATE TABLE t;"
s 1 "ALTER TABLE t ALTER COLUMN txt SET COMPRESSION lz4;"

c 'Еще раз загрузим данные и сравним.'
s 1 "\timing on"
s 1 "COPY t FROM '/tmp/gram.input';"
s 1 "\timing off"

s 1 "SELECT pg_table_size('t')/1024;"

c 'Алгоритм lz4 слегка уступает pglz по степени сжатия, однако работает значительно быстрее.'

c 'Удалим текстовый файл.'
e 'sudo rm -f /tmp/gram.input'

###############################################################################
stop_here
cleanup
demo_end
