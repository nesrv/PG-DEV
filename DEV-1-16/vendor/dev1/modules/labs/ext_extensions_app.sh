#!/bin/bash

. ../lib

init 14

cd
rm -rf bookfmt
sudo rm -f '/usr/share/postgresql/16/extension/bookfmt.control'
sudo rm -f '/usr/share/postgresql/16/extension/bookfmt--0.sql'
sudo rm -f '/usr/share/postgresql/16/extension/bookfmt--0--1.0.sql'

start_here

###############################################################################
h '1. Расширения для книжного формата'

c 'Сначала создадим «пустое» расширение без объектов.'

e "mkdir bookfmt"

f bookfmt/bookfmt.control conf << EOF
default_version = '0'
relocatable = true
encoding = UTF8
comment = 'Формат издания'
EOF

f bookfmt/bookfmt--0.sql pgsql << EOF
\echo Use "CREATE EXTENSION bookfmt" to load this file. \quit
EOF

f bookfmt/Makefile sh << EOF
EXTENSION = bookfmt
DATA = bookfmt--0.sql

PG_CONFIG = pg_config
PGXS := \$(shell \$(PG_CONFIG) --pgxs)
include \$(PGXS)
EOF

e "sudo make install -C bookfmt"

c 'Установим расширение.'

s 1 "CREATE EXTENSION bookfmt;"

c 'Теперь напишем скрипт для обновления, в котором добавим в расширение уже существующие в базе объекты.'

f bookfmt/bookfmt.control conf << EOF
default_version = '1.0'
relocatable = true
encoding = UTF8
comment = 'Формат издания'
EOF

f bookfmt/bookfmt--0--1.0.sql pgsql << EOF
\echo Use "CREATE EXTENSION bookfmt" to load this file. \quit

ALTER EXTENSION bookfmt ADD TYPE book_format;
ALTER EXTENSION bookfmt ADD FUNCTION book_format_to_text;
ALTER EXTENSION bookfmt ADD CAST (book_format AS text);
ALTER EXTENSION bookfmt ADD FUNCTION book_format_area;
ALTER EXTENSION bookfmt ADD FUNCTION book_format_cmp;
ALTER EXTENSION bookfmt ADD FUNCTION book_format_lt;
ALTER EXTENSION bookfmt ADD OPERATOR < (book_format, book_format);
ALTER EXTENSION bookfmt ADD FUNCTION book_format_le;
ALTER EXTENSION bookfmt ADD OPERATOR <= (book_format, book_format);
ALTER EXTENSION bookfmt ADD FUNCTION book_format_eq;
ALTER EXTENSION bookfmt ADD OPERATOR = (book_format, book_format);
ALTER EXTENSION bookfmt ADD FUNCTION book_format_gt;
ALTER EXTENSION bookfmt ADD OPERATOR > (book_format, book_format);
ALTER EXTENSION bookfmt ADD FUNCTION book_format_ge;
ALTER EXTENSION bookfmt ADD OPERATOR >= (book_format, book_format);
ALTER EXTENSION bookfmt ADD OPERATOR CLASS book_format_ops USING btree;
EOF

f bookfmt/Makefile sh << EOF
EXTENSION = bookfmt
DATA = bookfmt--0.sql bookfmt--0--1.0.sql

PG_CONFIG = pg_config
PGXS := \$(shell \$(PG_CONFIG) --pgxs)
include \$(PGXS)
EOF

e "sudo make install -C bookfmt"

c 'Выполним обновление:'

s 1 "ALTER EXTENSION bookfmt UPDATE;"

c 'Теперь все объекты объединены в расширение, которые мы при необходимости сможем развивать.'
c 'А для того чтобы расширением могли воспользоваться другие, надо подготовить файл «bookfmt--1.0.sql» с командами, создающими все необходимые объекты.'

###############################################################################
h '2. Проверка кодов ISBN'

c 'Установим расширение:'

s 1 "CREATE EXTENSION isn;"

s 1 "DO \$\$
DECLARE
    b_id bigint;
    i text;
    i10 isbn;
    i13 isbn13;
BEGIN
    FOR b_id, i IN SELECT book_id, additional->>'ISBN' FROM books LOOP
        BEGIN
            IF length(translate(i,'-','')) = 10 THEN
                i10 := isbn(i);
            ELSE
                i13 := isbn13(i);
            END IF;
        EXCEPTION
            WHEN others THEN
                RAISE NOTICE 'book_id=%: %', b_id, sqlerrm;
        END;
    END LOOP; 
END;
\$\$;"

c 'Проблемные данные часто встречаются в реальных системах. В данном случае они могут быть вызваны не только ошибками при вводе, но и неправильно указанным кодом в самой книге. Расширение isn имеет возможность работы в нестрогом режиме, допуская ошибки (но предупреждая о них).'

###############################################################################

stop_here
cleanup_app
