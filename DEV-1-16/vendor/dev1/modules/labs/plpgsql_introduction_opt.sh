#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Случайная строка заданного размера'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Вначале определим вспомогательную функцию для получения случайного целого числа в заданном диапазоне. Такую функцию легко написать на чистом SQL, но здесь представлен вариант на PL/pgSQL:'

s 1 "CREATE FUNCTION rnd_integer(min_value integer, max_value integer) 
RETURNS integer
AS \$\$
DECLARE
    retval integer;
BEGIN
    IF max_value <= min_value THEN 
       RETURN NULL; 
    END IF;

    retval := floor(
            (max_value+1 - min_value)*random()
	)::integer + min_value;
    RETURN retval;
END
\$\$ STRICT LANGUAGE plpgsql;"

c 'Проверяем работу:'
s 1 'SELECT rnd_integer(0,1) as "0 - 1",
          rnd_integer(1,365) as "1 - 365",
          rnd_integer(-30,30) as "-30 - +30"
   FROM generate_series(1,10);'

c 'Функция гарантирует равномерное распределение случайных значений по всему диапазону, включая граничные значения:'

s 1 'SELECT rnd_value, count(*)
FROM (
    SELECT rnd_integer(1,5) AS rnd_value 
    FROM generate_series(1,100_000)
)
GROUP BY rnd_value ORDER BY rnd_value;'

c 'Теперь можно приступить к написанию функции для получения случайной строки заданного размера. Будем использовать функцию rnd_integer для получения случайного символа из списка.'

s 1 "CREATE FUNCTION rnd_text(
   len int,
   list_of_chars text DEFAULT 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюяABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789'
) RETURNS text
AS \$\$
DECLARE
    len_of_list CONSTANT integer := length(list_of_chars);
    i integer;
    retval text := '';
BEGIN
    FOR i IN 1 .. len
    LOOP
        -- добавляем к строке случайный символ
        retval := retval ||
                  substr(list_of_chars, rnd_integer(1,len_of_list),1);
    END LOOP;
    RETURN retval;
END
\$\$ STRICT LANGUAGE plpgsql;"

c 'Проверяем:'

s 1 'SELECT rnd_text(rnd_integer(1,30)) FROM generate_series(1,10);'

###############################################################################
h '2. Игра в наперстки'

c 'Для загадывания и угадывания наперстка используем rnd_integer(1,3).'

s 1 "DO \$\$
DECLARE
    x integer;
    choice integer;
    new_choice integer;
    remove integer;
    total_games integer := 1000;
    old_choice_win_counter integer := 0;
    new_choice_win_counter integer := 0;
BEGIN
    FOR i IN 1 .. total_games
    LOOP
        -- Загадываем выигрышный наперсток
        x := rnd_integer(1,3);
    
        -- Игрок делает выбор
        choice := rnd_integer(1,3);
        
        -- Убираем один неверный ответ, кроме выбора игрока
        FOR i IN 1 .. 3
        LOOP
            IF i NOT IN (x, choice) THEN
                remove := i;
                EXIT;
            END IF;
        END LOOP;
    
        -- Нужно ли игроку менять свой выбор?    
        -- Что лучше: оставить choice или заменить его на оставшийся?
    
        -- Измененный выбор
        FOR i IN 1 .. 3
        LOOP
            IF i NOT IN (remove, choice) THEN
                new_choice := i;
                EXIT;
            END IF;
        END LOOP;
    
        -- Или начальный, или новый выбор обязательно выиграют
        IF choice = x THEN
            old_choice_win_counter := old_choice_win_counter + 1;
        ELSIF new_choice = x THEN
            new_choice_win_counter := new_choice_win_counter + 1;
        END IF;
    END LOOP;

    RAISE NOTICE 'Выиграл начальный выбор:  % из %', 
        old_choice_win_counter, total_games;
    RAISE NOTICE 'Выиграл измененный выбор: % из %', 
        new_choice_win_counter, total_games;
END
\$\$;"

c "Вначале мы выбираем 1 из 3, поэтому вероятность начального выбора 1/3. Если же выбор изменить, то изменится и вероятность на противоположные 2/3."
c "Таким образом, вероятность выиграть при смене выбора выше. Поэтому есть смысл выбор поменять."

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
