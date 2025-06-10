#!/bin/bash

. ../lib

init

cd
rm -rf typo
sudo rm -f '/usr/share/postgresql/16/extension/typo.control'
sudo rm -f '/usr/share/postgresql/16/extension/typo--1.0.sql'

start_here

###############################################################################
h '1. Расширение для подготовки текста'

e "mkdir typo"

c 'В управляющем файле указываем relocatable = false:'

f typo/typo.control conf << EOF
default_version = '1.0'
relocatable = false
encoding = UTF8
comment = 'Подготовка текста по настраиваемым правилам'
EOF

c 'Создаем файл с командами. В таблице предусматриваем столбец seeded, чтобы отличать предустановленные правила от пользовательских.'

f typo/typo--1.0.sql pgsql << EOF
\echo Use "CREATE EXTENSION typo" to load this file. \quit

CREATE TABLE typo_rules (
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    pattern text NOT NULL,
    replace_by text NOT NULL,
    seeded boolean DEFAULT false
);
GRANT SELECT ON typo_rules TO public;
INSERT INTO typo_rules(pattern, replace_by, seeded) VALUES
    ('(^|\s)\"(\S)',   '\1«\2', true),
    ('(\S)\"(\s|$)',   '\1»\2', true),
    ('(^|\s)-(\s|$)', '\1—\2', true);
EOF

c 'Добавляем в тот же файл функцию. В ней квалифицируем таблицу именем схемы, чтобы не зависеть от настройки пути поиска. Имя схемы задается макросом:'

f typo/typo--1.0.sql pgsql << EOF
CREATE FUNCTION typo(INOUT s text) AS \$\$
DECLARE
    r record;
BEGIN
    FOR r IN (
        SELECT pattern, replace_by
        FROM @extschema@.typo_rules
        ORDER BY id
    )
    LOOP
        s := regexp_replace(s, r.pattern, r.replace_by, 'g');
    END LOOP;
END;
\$\$ LANGUAGE plpgsql STABLE;
EOF

c 'Для того чтобы утилита pg_dump корректно выгружала пользовательские правила, вызываем специальную функцию не только для таблицы, но и для последовательности, которая используется для первичного ключа.'

f typo/typo--1.0.sql pgsql << EOF
SELECT pg_extension_config_dump('typo_rules', 'WHERE NOT seeded');
SELECT pg_extension_config_dump('typo_rules_id_seq', '');
EOF

c 'Makefile и установка расширения в систему:'

f typo/Makefile sh << EOF
EXTENSION = typo
DATA = typo--1.0.sql

PG_CONFIG = pg_config
PGXS := \$(shell \$(PG_CONFIG) --pgxs)
include \$(PGXS)
EOF

e "sudo make install -C typo"

###############################################################################
h '2. Проверка'

c 'Создаем базу данных и схему, и устанавливаем расширение:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE SCHEMA typo;"
s 1 "CREATE EXTENSION typo SCHEMA typo;"

c 'При установке макрос был автоматически заменен на имя выбранной схемы:'

s 1 '\sf typo.typo' pgsql

c 'Проверим:'

s 1 "SELECT typo.typo(
    'Вдруг попугай заорал: \"Овер-рсан! Овер-рсан!\" - и все замерли.'
);"

c 'Добавим правило:'

s 1 "INSERT INTO typo.typo_rules(pattern, replace_by)
    VALUES (' +', ' ');"

s 1 "SELECT typo.typo(
    '-  Будет, -  сказал Дрозд. - Я уже   букву \"к\" нарисовал.'
);"

psql_close 1

c 'Выгружаем копию базы данных и восстанавливаемся из нее (при восстановлении база данных будет удалена и создана заново):'

e "pg_dump --clean --create $TOPIC_DB > $TOPIC_DB.dump"
e "psql -f $TOPIC_DB.dump"

c 'Обратите внимание, что последней командой было установлено корректное значение последовательности. Если бы функция pg_extension_config_dump была вызвана только для таблицы, этого бы не произошло.'

psql_open A 1 $TOPIC_DB

c 'Проверяем:'

s 1 "INSERT INTO typo.typo_rules(pattern, replace_by)
    VALUES ('\.\.\.', '…');"

s 1 "SELECT typo.typo(
    'Как это там... Соус пикан. Полстакана уксусу, две луковицы... и перчик.'
);"

###############################################################################

stop_here
cleanup
