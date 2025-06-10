#!/bin/bash

. ../lib

init

rm -rf $USERDIR/uom
sudo rm -f '/usr/share/postgresql/16/extension/uom.control'
sudo rm -f '/usr/share/postgresql/16/extension/uom--1.0.sql'
sudo rm -f '/usr/share/postgresql/16/extension/uom--1.0--1.1.sql'
sudo rm -f '/usr/share/postgresql/16/extension/uom--1.1--1.2.sql'

start_here 6

###############################################################################
h 'Создание расширения'

c 'Создадим простое расширение — конвертер единиц измерения, и назовем его uom (units of measure).'
c 'Начнем с каталога, в котором будем создавать необходимые файлы:'

cd
e "mkdir $USERDIR/uom"

c 'Сначала создадим управляющий файл с настройками (мы можем сделать это в любом текстовом редакторе).'

ul 'default_version определяет версию по умолчанию, без этого параметра версию придется указывать явно;'
ul 'relocatable говорит о том, что расширение можно перемещать из схемы в схему (мы поговорим об этом чуть позже);'
ul 'encoding требуется, если используются символы, отличные от ASCII;'
ul 'comment определяет комментарий к расширению.'

f $USERDIR/uom/uom.control conf << EOF
default_version = '1.0'
relocatable = true
encoding = UTF8
comment = 'Единицы измерения'
EOF

c 'Это не все возможные параметры; полный список можно узнать из документации.'

p

c 'Теперь займемся файлом с командами, создающими объекты расширения.'

ul 'Первая строка файла предотвращает случайный запуск скрипта вручную.'
ul 'Все команды будут выполнены в одной транзакции — неявном блоке BEGIN ... END. Поэтому команды управления транзакциями (и служебные команды, такие, как VACUUM) здесь не допускаются.'
ul 'Путь поиска (параметр search_path) будет установлен на единственную схему — ту, в которой создаются объекты расширения.'

f $USERDIR/uom/uom--1.0.sql pgsql << EOF
\echo Use "CREATE EXTENSION uom" to load this file. \quit

-- Справочник единиц измерения
CREATE TABLE uoms (
    uom text PRIMARY KEY,
    k numeric NOT NULL
);
GRANT SELECT ON uoms TO public;
INSERT INTO uoms(uom,k) VALUES ('м',1), ('км',1000), ('см',0.01);

-- Функция для перевода значения из одной единицы в другую
CREATE FUNCTION convert(value numeric, uom_from text, uom_to text) RETURNS numeric
LANGUAGE sql STABLE STRICT
RETURN convert.value *
    (SELECT k FROM uoms WHERE uom = convert.uom_from) /
    (SELECT k FROM uoms WHERE uom = convert.uom_to);
EOF

c 'Чтобы PostgreSQL нашел созданные нами файлы, они должны оказаться в каталоге SHAREDIR/extension. Значение SHAREDIR можно узнать так:'

e "pg_config --sharedir"

c 'Например, посмотрим на файлы расширения pg_background:'

e 'ls `pg_config --sharedir`/extension/pg_background*'

p

c "Конечно, файлы расширения можно скопировать вручную, но стандартный способ — воспользоваться утилитой make. Ей понадобится Makefile, который должен выглядеть, как показано ниже."

ul 'Переменная EXTENSION задает имя расширения;'
ul 'Переменная DATA определяет список файлов, которые надо скопировать в SHAREDIR (кроме управляющего);'
ul 'Последние строки не меняются. Они подключают специальный Makefile для расширений, который содержит всю необходимую логику сборки и установки. Важно, чтобы утилита pg_config была доступна — иначе неизвестны пути, по которым установлен PostgreSQL.'

f $USERDIR/uom/Makefile sh << EOF
EXTENSION = uom
DATA = uom--1.0.sql

PG_CONFIG = pg_config
PGXS := \$(shell \$(PG_CONFIG) --pgxs)
include \$(PGXS)
EOF

c 'Теперь выполним make install в каталоге расширения:'

e "sudo make install -C $USERDIR/uom"

c 'Создадим базу данных и подключимся к ней:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Проверим, доступно ли наше расширение?'

s 1 "SELECT * FROM pg_available_extensions WHERE name = 'uom';"

c 'Попробуем создать в новой базе расширение uom:'

s 1 "CREATE EXTENSION uom;"

c 'Мы не указали версию, поэтому было взято значение из управляющего файла (1.0).'

s 1 "SELECT * FROM uoms;"
s 1 "SELECT convert(2, 'км', 'м');"

c 'Все работает.'

c 'Само расширение не относится к какой-либо схеме, но объекты расширения — относятся. В какой схеме они созданы?'

s 1 '\dt uoms'

c 'Объекты установлены в схему, в которой они были бы созданы по умолчанию; в данном случае — public. При создании расширения мы можем указать эту схему явно:'

s_fake 1 "CREATE EXTENSION uom SCHEMA public;"

c 'Поскольку мы указали в управляющем файле, что расширение переносимо (relocatable), его можно переместить в другую схему:'

s 1 "CREATE SCHEMA uom;"
s 1 "ALTER EXTENSION uom SET SCHEMA uom;"

c 'Теперь все объекты находятся в схеме uom:'

s 1 '\dt uom.*'
s 1 '\df uom.*'

c 'Можно ли прочитать данные из таблицы без указания схемы, где она расположена?'

s 1 "SELECT * FROM uoms;"

c 'Нет, потому что теперь таблица не находится в пути поиска.'

c 'А будет ли работать функция, если при ее вызове мы явно укажем схему? Напомним, что в определении тела функции обращение к таблице не включало название схемы.'

s 1 "SELECT uom.convert(2, 'км', 'м');"

c 'Да, потому что код функции был оформлен в современном стиле стандарта SQL, а значит еще на этапе создания был выполнен его разбор и теперь обращение к таблице производится по ее идентификатору, а не по символическому имени.'

c 'Позаботимся о путях поиска; данные из таблицы читаются:'

s 1 "SET search_path = uom, public;"
s 1 "SELECT * FROM uoms;"

c 'Отметим, что некоторые расширения не допускают перемещения, но это бывает нечасто.'

P 8

###############################################################################
h 'Версии расширения и обновление'

c 'При некотором размышлении мы можем сообразить, что не любые единицы допускают преобразование. Например, метры нельзя пересчитать в килограммы. Создадим версию 1.1 нашего расширения, которая это учитывает.'

c 'В управляющем файле исправим версию на 1.1:'

f $USERDIR/uom/uom.control conf << EOF
default_version = '1.1'
relocatable = true
encoding = UTF8
comment = 'Единицы изменения'
EOF

c 'И создадим файл с командами для обновления:'

f $USERDIR/uom/uom--1.0--1.1.sql pgsql << EOF
\echo Use "CREATE EXTENSION uom" to load this file. \quit

-- Все, что было, отнесем к мерам длины
ALTER TABLE uoms ADD uom_class text NOT NULL DEFAULT 'длина';

-- Добавим единицы измерения массы
INSERT INTO uoms(uom,k,uom_class) VALUES
    ('г', 1,'масса'), ('кг', 1_000,'масса'),
    ('ц', 100_000,'масса'), ('т', 1_000_000,'масса');

-- Функция для перевода значения из одной единицы в другую
CREATE OR REPLACE FUNCTION convert(
    value numeric,
    uom_from text,
    uom_to text
)
RETURNS numeric AS \$\$
DECLARE
    uoms_from uoms;
    uoms_to uoms;
BEGIN
    SELECT * INTO uoms_from FROM uoms WHERE uom = convert.uom_from;
    SELECT * INTO uoms_to FROM uoms WHERE uom = convert.uom_to;
    IF uoms_from.uom_class != uoms_to.uom_class THEN
        RAISE EXCEPTION 'Невозможно преобразовать : % -> %',
            uoms_from.uom_class, uoms_to.uom_class;
    END IF;
    RETURN convert.value * uoms_from.k / uoms_to.k;
END;
\$\$ LANGUAGE plpgsql STABLE STRICT;
EOF

c 'Добавим в Makefile новый файл в список DATA:'

f $USERDIR/uom/Makefile sh << EOF
EXTENSION = uom
DATA = uom--1.0.sql uom--1.0--1.1.sql

PG_CONFIG = pg_config
PGXS := \$(shell \$(PG_CONFIG) --pgxs)
include \$(PGXS)
EOF

c 'Выполним make install, чтобы разместить файлы расширения:'

e "sudo make install -C $USERDIR/uom"

c 'Какие версии расширения нам доступны?'

s 1 "SELECT name, version, installed
FROM pg_available_extension_versions
WHERE name = 'uom';"

c 'Какие пути обновления доступны?'

s 1 "SELECT * FROM pg_extension_update_paths('uom');"

c 'Очевидно, путь один. Заметьте, что если бы мы создали файл «uom--1.1--1.0.sql», можно было бы «понизить версию». Для механизма расширений имена версий ничего не значат.'

c 'Выполним обновление:'

s 1 "ALTER EXTENSION uom UPDATE;"

c 'Теперь нам доступен новый функционал:'

s 1 "SELECT convert(2, 'ц', 'кг');"
s 1 "SELECT convert(1, 'м', 'кг');"

p

###############################################################################
h 'Утилита pg_dump'

c 'Что попадает в резервную копию базы данных, созданную с помощью утилиты pg_dump?'

e "pg_dump $TOPIC_DB | grep -v '^--'" pgsql

ul 'Вначале идут установки различных параметров сервера;'
ul 'Объекты расширения не попадают в резервную копию, вместо этого выполняется команда CREATE EXTENSION — это позволяет сохранить зависимости между объектами.'

p

c 'В процессе работы с расширением пользователь может захотеть расширить справочник единиц измерения:'

s 1 "INSERT INTO uoms(uom,k,uom_class) VALUES
    ('верста',1066.8,'длина'), ('сажень',2.1336,'длина');"

c 'Что теперь попадает в резервную копию?'

e "pg_dump $TOPIC_DB | grep -v '^--'" pgsql

c 'Сделанные пользователем изменения будут потеряны.'

p

c 'Но этого можно избежать, если мы сможем разделить предустановленные значения и пользовательские. Подготовим версию 1.2 расширения.'

s 1 "DELETE FROM uoms WHERE uom IN ('верста', 'сажень');"

c 'В управляющем файле исправим версию на 1.2:'

f $USERDIR/uom/uom.control conf << EOF
default_version = '1.2'
relocatable = true
encoding = UTF8
comment = 'Единицы измерения'
EOF

c 'Создадим файл с командами для обновления. Вызов функции pg_extension_config_dump определяет, какие строки таблицы требуют выгрузки.'

f $USERDIR/uom/uom--1.1--1.2.sql pgsql << EOF
\echo Use "CREATE EXTENSION uom" to load this file. \quit

-- Добавляем признак предустановленных данных
ALTER TABLE uoms ADD seeded boolean NOT NULL DEFAULT false;
UPDATE uoms SET seeded = true;

SELECT pg_extension_config_dump('uoms', 'WHERE NOT seeded');
EOF

c 'Добавим в Makefile новый файл в список DATA:'

f $USERDIR/uom/Makefile sh << EOF
EXTENSION = uom
DATA = uom--1.0.sql uom--1.0--1.1.sql uom--1.1--1.2.sql

PG_CONFIG = pg_config
PGXS := \$(shell \$(PG_CONFIG) --pgxs)
include \$(PGXS)
EOF

c 'Выполним make install, чтобы разместить файлы расширения:'

e "sudo make install -C $USERDIR/uom"

c 'И выполним обновление:'

s 1 "ALTER EXTENSION uom UPDATE;"

c 'Повторим эксперимент:'

s 1 "INSERT INTO uoms(uom, k, uom_class) VALUES
    ('верста', 1066.8, 'длина'), ('сажень', 2.1336, 'длина');"

c 'Что теперь попадает в резервную копию?'

e "pg_dump $TOPIC_DB | grep -v '^--'" pgsql

c 'На этот раз все правильно: после создания расширения в таблицу добавляются строки, созданные пользователем.'

###############################################################################

stop_here
cleanup
demo_end
