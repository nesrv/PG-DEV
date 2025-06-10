#!/bin/bash

. ../lib

init

start_here 10

###############################################################################
h 'Тип bytea и TOAST'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c "По умолчанию двоичные данные выводятся в шестнадцатеричном формате."
s 1 "SHOW bytea_output;"

c "Значения начинаются с '\x', далее каждый байт представлен двумя шестнадцатеричными цифрами:"
s 1 "SELECT 'Hello'::bytea;"

c 'Добавим нулевой символ к строке:'
s 1 "SELECT 'Hello'::bytea || '\x00'::bytea;"

c 'Шестнадцатеричный формат появился в версии 9.0. До этого был доступен только формат «спецпоследовательностей».'
s 1 "SET bytea_output = 'escape';"

c 'В этом формате ASCII-символы отображаются как есть, а остальные представлены спецпоследовательностями:'
s 1 "SELECT 'Hello'::bytea || '\x00'::bytea;"

c 'Параметр bytea_output определяет только формат вывода двоичных данных. Входные данные принимаются в любом из этих двух форматов.'

s 1 "RESET bytea_output;"

c 'Теперь создадим таблицу со столбцом типа bytea.'

s 1 'CREATE TABLE demo_bytea(
  filename text, 
  data bytea
);'

c "Таблица TOAST создается автоматически для хранения больших значений data и filename (значения типа text также могут быть большими). Найдем имя служебной таблицы:"

s 1 "SELECT reltoastrelid::regclass AS toast_table 
FROM pg_class 
WHERE oid = 'demo_bytea'::regclass;"
export TOAST_TABLE=`sudo -i -u $OSUSER psql -A -t -X -d $TOPIC_DB -c "SELECT reltoastrelid::regclass::text FROM pg_class WHERE oid = 'demo_bytea'::regclass;"`
export TOAST_INDEX="${TOAST_TABLE}_index"

c 'Служебные таблицы TOAST всегда располагаются в специальной схеме pg_toast — чтобы не пересекаться с обычными объектами базы данных. Получить список TOAST-таблиц можно командой psql:'
s 1 "\dtS $TOAST_TABLE*"

p

c 'Посмотрим на структуру TOAST-таблицы:'
s 1 "\d $TOAST_TABLE"

ul 'chunk_id — идентификатор значения,'
ul 'chunk_seq — порядковый номер фрагмента значения,'
ul 'chunk_data — данные фрагмента.'

c 'Можно обратить внимание, что вывод команды \d для TOAST-таблиц содержит название основной таблицы.'

c 'Доступ к значениям в TOAST всегда осуществляется по индексу. Это самый быстрый способ получить все фрагменты одного значения для склейки, но доступ ко всем значениям будет заведомо неэффективен.'

c 'Кроме того, чтение большого объема данных из TOAST-таблиц может приводить к вытеснению полезных данных из буферного кеша. Механизм буферного кольца, предотвращающий массовое вытеснение, для TOAST-таблиц не используется, так как задействуется только при полном последовательном сканировании таблицы, но не при индексном доступе.'

p

export FILENAME="/tmp/bookstore2.sql"
export FNAME="$(basename $FILENAME)"

c "Добавим в demo_bytea строку. В качестве данных возьмем логическую резервную копию базы данных приложения."

e "pg_dump -d bookstore2 > $FILENAME"
e "ls -l $FILENAME"

c "Заметим время вставки."
si 1 '\timing on'

c 'Для считывания файла воспользуемся встроенной функцией pg_read_binary_file.'
s 1 "INSERT INTO demo_bytea(filename, data) VALUES (
    '$FNAME',
    pg_read_binary_file('$FILENAME')
);"

si 1 '\timing off'

c "Использование TOAST прозрачно для приложения. Нам не нужно обращаться к служебной таблице в запросах. Вот первые 16 байт загруженного файла в двоичном виде:"

s 1 "SELECT substring(data,1,16) FROM demo_bytea;"

c 'Общий размер загруженного значения соответствует размеру файла:'
s 1 "SELECT length(data) FROM demo_bytea;"

c "Однако размер таблицы demo_bytea составляет всего одну страницу, данных загруженного файла в ней нет:"
s 1 "SELECT pg_relation_size('demo_bytea');"

c "Значение столбца data попало в TOAST-таблицу. Можно убедиться, что в служебной таблице появилось одно значение:"
s 1 "SELECT count(distinct(chunk_id)) FROM $TOAST_TABLE;"

c 'Сколько места требуется для хранения TOAST-таблицы, если сравнивать с размером файла: меньше, больше или ровно столько же?'
s 1 "SELECT pg_relation_size('$TOAST_TABLE');"

c 'Почему потребовалось меньше места?'
s 1 '\d+ demo_bytea'

c 'Стратегия хранения extended предполагает сжатие данных при помещении в TOAST. А текстовые данные хорошо сжимаются.'

c 'Начиная с PostgreSQL 14 появилась возможность выбора метода сжатия: pglz (используется по умолчанию) и lz4. Изменим метод сжатия для столбца data и повторим наш опыт, предварительно опустошив таблицу.'

s 1 'ALTER TABLE demo_bytea ALTER COLUMN data SET COMPRESSION lz4;'
s 1 "TRUNCATE demo_bytea;"

s 1 '\timing on'

s 1 "INSERT INTO demo_bytea(filename, data) VALUES (
    '$FNAME',
    pg_read_binary_file('$FILENAME')
);"
s 1 '\timing off'

c 'Вставка данных выполнилась заметно быстрее, но места для сжатых данных потребуется больше — lz4 сжимает данные не так эффективно:'
s 1 "SELECT pg_relation_size('$TOAST_TABLE');"

c 'Сжатие вообще можно запретить, выбрав стратегию external:'
s 1 'ALTER TABLE demo_bytea ALTER COLUMN data SET STORAGE external;'

c 'Это изменение будет действовать только для новых строк, поэтому снова опустошим таблицу и загрузим файл заново.'
s 1 "TRUNCATE demo_bytea;"
s 1 "INSERT INTO demo_bytea(filename, data) VALUES (
    '$FNAME',
    pg_read_binary_file('$FILENAME')
);"

c 'Сколько теперь потребуется места для хранения TOAST-таблицы, если сравнивать с размером исходного файла: меньше, больше или ровно столько же?'
s 1 "SELECT pg_relation_size('$TOAST_TABLE');"

c 'Теперь для хранения используется немного больше места. Почему?'

s 1 "SELECT chunk_id, chunk_seq, substring(chunk_data,1,16),
    length(chunk_data)
FROM $TOAST_TABLE
ORDER BY 1,2 LIMIT 3;"

c 'На размер повлияли накладные расходы на хранение фрагментов в отдельных строках с дополнительными столбцами и служебной информацией.'

P 13

###############################################################################
h 'Использование large objects'

c 'Большие объекты хранятся в таблице системного каталога pg_largeobject, структура которой похожа на структуру TOAST-таблицы.'
s 1 "\d pg_largeobject"

c "Создадим таблицу для хранения ссылок на большие объекты."
s 1 "CREATE TABLE demo_largeobject(
  filename text,
  link oid
);"

c "Для работы с большими объектами будем использовать интерфейсные функции SQL."
s 1 "INSERT INTO demo_largeobject VALUES (
    '$FNAME',
    lo_import('$FILENAME')
);"

c "Функция lo_import загружает файл с сервера в pg_largeobject и возвращает указатель на него (OID)."

c "Функция lo_get считывает указанную часть значения:"
s 1 "SELECT filename, link, lo_get(link,1,16) FROM demo_largeobject;"

c 'Что будет, если удалить строку из таблицы demo_largeobject?'
s 1 "DELETE FROM demo_largeobject;"

c 'Строка удалится, а большой объект станет «потерянным»:'
s 1 "\lo_list"

c 'Дополнительная утилита vacuumlo, поставляемая с сервером, позволяет найти большие объекты, на которые не осталось ссылок, и удалить их:'
e "vacuumlo --verbose $TOPIC_DB"
s 1 "\lo_list"

c 'Для предотвращения потери ссылок также можно воспользоваться расширением lo.'
s 1 "CREATE EXTENSION lo;"

c 'Расширение создает тип данных lo (обертка над oid) и функцию lo_manage для использования в триггерных функциях.'
s 1 "CREATE TABLE demo_lo (filename text, link lo);"
s 1 "CREATE TRIGGER t_link
BEFORE UPDATE OR DELETE ON demo_lo
FOR EACH ROW
EXECUTE FUNCTION lo_manage(link);"

c "Загрузим большой объект и поместим ссылку на него в таблицу."
s 1 "INSERT INTO demo_lo VALUES (
    '$FNAME',
    lo_import('$FILENAME')
);"

c "Убедимся, что все на месте, и удалим."
s 1 "SELECT filename, lo_get(link,1,16) FROM demo_lo;"
s 1 "DELETE FROM demo_lo;"

s 1 "\lo_list"

c 'Табличный триггер удалил связанный большой объект.'

###############################################################################

stop_here
cleanup
demo_end
