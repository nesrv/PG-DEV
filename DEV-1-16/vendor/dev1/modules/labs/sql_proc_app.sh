#!/bin/bash

. ../lib

init_app
roll_to 9

start_here

###############################################################################
h '1. Устранение дубликатов'

c 'В целях проверки добавим второго Пушкина:'

s 1 "INSERT INTO authors(last_name, first_name, middle_name)
    VALUES ('Пушкин', 'Александр', 'Сергеевич');"

s 1 "SELECT last_name, first_name, middle_name, count(*)
FROM authors
GROUP BY last_name, first_name, middle_name;"

c 'Задачу устранения дубликатов можно решить разными способами. Например, так:'

s 1 "CREATE PROCEDURE authors_dedup()
LANGUAGE sql
BEGIN ATOMIC
DELETE FROM authors
WHERE author_id IN (
    SELECT author_id
    FROM (
        SELECT author_id,
               row_number() OVER (
                   PARTITION BY first_name, last_name, middle_name
                   ORDER BY author_id
               ) AS rn
        FROM authors
    ) t
    WHERE t.rn > 1
);
END;"

s 1 "CALL authors_dedup();"

s 1 "SELECT last_name, first_name, middle_name, count(*)
FROM authors
GROUP BY last_name, first_name, middle_name;"

###############################################################################
h '2. Ограничение целостности'

c 'Создать подходящее ограничение целостности мешает тот факт, что отчество может быть неопределенным (NULL). Неопределенные значения считаются различными, поэтому ограничение'

s_fake 1 "UNIQUE(first_name, last_name, middle_name)"

c 'не помешает добавить второго Джонатана Свифта без отчества.'
c 'Задачу можно решить, создав уникальный индекс:'


s 1 "CREATE UNIQUE INDEX authors_full_name_idx ON authors(
    last_name, first_name, coalesce(middle_name,'')
);"

c 'Проверим:'

s 1 "INSERT INTO authors(last_name, first_name)
    VALUES ('Свифт', 'Джонатан');"
s 1 "INSERT INTO authors(last_name, first_name, middle_name)
    VALUES ('Пушкин', 'Александр', 'Сергеевич');"

###############################################################################

stop_here
cleanup_app
