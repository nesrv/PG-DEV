#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Таблица'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE TABLE animals(
    id     integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    yes_id integer REFERENCES animals(id),
    no_id  integer REFERENCES animals(id),
    name   text
);"

s 1 "INSERT INTO animals(name) VALUES
    ('млекопитающее'), ('слон'), ('черепаха');"
s 1 "UPDATE animals SET yes_id = 2, no_id = 3 WHERE id = 1;"
s 1 "SELECT * FROM animals ORDER BY id;"

c 'Первая строка считается корнем дерева.'

###############################################################################
h '2. Функции'

s 1 "CREATE FUNCTION start_game(
    OUT context integer,
    OUT question text
)
AS \$\$
DECLARE
    root_id CONSTANT integer := 1;
BEGIN
    SELECT id, name||'?'
    INTO context, question 
    FROM animals 
    WHERE id = root_id;
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE FUNCTION continue_game(
    INOUT context integer, 
    IN answer boolean, 
    OUT you_win boolean, 
    OUT question text
)
AS \$\$
DECLARE
    new_context integer;
BEGIN
    SELECT CASE WHEN answer THEN yes_id ELSE no_id END
    INTO new_context
    FROM animals
    WHERE id = context;

    IF new_context IS NULL THEN
        you_win := NOT answer;
        question := CASE
            WHEN you_win THEN 'Сдаюсь'
            ELSE 'Вы проиграли'
        END;
    ELSE
        SELECT id, null, name||'?'
        INTO context, you_win, question
        FROM animals
        WHERE id = new_context;
    END IF;
END
\$\$ LANGUAGE plpgsql;"

s 1 "CREATE FUNCTION end_game(
    IN context integer,
    IN name text, 
    IN question text
) RETURNS void
AS \$\$
DECLARE
    new_animal_id integer;
    new_question_id integer;
BEGIN
    INSERT INTO animals(name) VALUES (name)
        RETURNING id INTO new_animal_id;
    INSERT INTO animals(name) VALUES (question)
        RETURNING id INTO new_question_id;
    UPDATE animals SET yes_id = new_question_id
    WHERE yes_id = context;
    UPDATE animals SET  no_id = new_question_id
    WHERE  no_id = context;
    UPDATE animals SET yes_id = new_animal_id, no_id = context
    WHERE id = new_question_id;
END
\$\$ LANGUAGE plpgsql;"

###############################################################################
h '3. Пример сеанса игры'

c 'Загадываем слово «кит».'

s 1 "SELECT * FROM start_game();"
s 1 "SELECT * FROM continue_game(1,true);"
s 1 "SELECT * FROM continue_game(2,false);"
s 1 "SELECT * FROM end_game(2,'кит','живет в воде');"

c 'Теперь в таблице:'

s 1 "SELECT * FROM animals ORDER BY id;"

c 'Снова загадали «кит».'

s 1 "SELECT * FROM start_game();"
s 1 "SELECT * FROM continue_game(1,true);"
s 1 "SELECT * FROM continue_game(5,true);"
s 1 "SELECT * FROM continue_game(4,true);"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
