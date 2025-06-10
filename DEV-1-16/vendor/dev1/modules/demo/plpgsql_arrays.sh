#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

start_here 4

###############################################################################
h 'Инициализация и обращение к элементам'

c 'Объявление переменной и инициализация массива целиком:'

s 1 "DO \$\$
DECLARE
    a integer[2]; -- размер игнорируется
BEGIN
    a := ARRAY[10,20,30];
    RAISE NOTICE '%', a;
    -- по умолчанию элементы нумеруются с единицы
    RAISE NOTICE 'a[1] = %, a[2] = %, a[3] = %', a[1], a[2], a[3];
    -- срез массива
    RAISE NOTICE 'Срез [2:3] = %', a[2:3];
    -- присваиваем значения срезу массива
    a[2:3] := ARRAY[222,333];
    -- выводим весь массив
    RAISE NOTICE '%', a;
END;
\$\$ LANGUAGE plpgsql;"

c 'Одномерный массив можно заполнять и поэлементно — при необходимости он автоматически расширяется. Если пропустить какие-то элементы, они получают неопределенные значения.'
c 'Что будет выведено?'

s 1 "DO \$\$
DECLARE
    a integer[];
BEGIN
    a[2] := 10;
    a[3] := 20;
    a[6] := 30;
    RAISE NOTICE '%', a;
END;
\$\$ LANGUAGE plpgsql;"

c 'Поскольку нумерация началась не с единицы, перед самим массивом дополнительно выводится диапазон номеров элементов.'

c 'Мы можем определить составной тип и создать массив из элементов этого типа:'

s 1 "CREATE TYPE currency AS (amount numeric, code text);"

s 1 "DO \$\$
DECLARE
    c currency[];  -- массив из элементов составного типа
BEGIN
  -- присваиваем значения отдельным элементам
    c[1].amount := 10;  c[1].code := 'RUB';
    c[2].amount := 50;  c[2].code := 'KZT';
    RAISE NOTICE '%', c;
END
\$\$ LANGUAGE plpgsql;"

c 'Еще один способ получить массив — создать его из подзапроса:'

s 1 "DO \$\$
DECLARE
    a integer[];
BEGIN
    a := ARRAY( SELECT n FROM generate_series(1,3) n );
    RAISE NOTICE '%', a;
END
\$\$ LANGUAGE plpgsql;"

c 'Можно и наоборот, массив преобразовать в таблицу:'

s 1 "SELECT unnest( ARRAY[1,2,3] );"

c 'Интересно, что выражение IN со списком значений преобразуется в поиск по массиву:'

s 1 "EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) g(id) WHERE id IN (1,2,3);"

p

c 'Двумерный массив — прямоугольная матрица, память под которую выделяется при инициализации. Литерал выглядит как массив массивов, имеющих одинаковое число элементов. Здесь мы использовали другой способ инициализации — с помощью символьной строки.'
c 'После инициализации многомерный массив уже нельзя расширить.'

s 1 "DO \$\$
DECLARE
    a integer[][] := '{
        { 10, 20, 30},
        {100,200,300}
    }';
BEGIN
    RAISE NOTICE 'Двумерный массив : %', a;
    RAISE NOTICE 'Неограниченный срез массива [2:] = %', a[2:];
    -- присваиваем значения этому срезу
    a[2:] := ARRAY[ARRAY[111, 222, 333]];
    -- снова выводим весь массив
    RAISE NOTICE '%', a;
    -- расширять нельзя ни по какому измерению
    a[4][4] := 1;
END
\$\$ LANGUAGE plpgsql;"

P 6

###############################################################################
h 'Массивы и циклы'

c 'Цикл можно организовать, итерируя индексы элементов массива. Второй параметр функций array_lower и array_upper — номер размерности (единица для одномерных массивов).'

s 1 "DO \$\$
DECLARE
    a integer[] := ARRAY[10,20,30];
BEGIN
    FOR i IN array_lower(a,1)..array_upper(a,1) LOOP 
        RAISE NOTICE 'a[%] = %', i, a[i];
    END LOOP;
END
\$\$ LANGUAGE plpgsql;"

c 'Если индексы не нужны, то проще итерировать сами элементы:'

s 1 "DO \$\$
DECLARE
    a integer[] := ARRAY[10,20,30];
    x integer;
BEGIN
    FOREACH x IN ARRAY a LOOP 
        RAISE NOTICE '%', x;
    END LOOP;
END
\$\$ LANGUAGE plpgsql;"

c 'Итерация индексов в двумерном массиве:'

s 1 "DO \$\$
DECLARE
    -- можно и без двойных квадратных скобок
    a integer[] := ARRAY[
        ARRAY[ 10, 20, 30],
        ARRAY[100,200,300]
    ];
BEGIN
    FOR i IN array_lower(a,1)..array_upper(a,1) LOOP -- по строкам
        FOR j IN array_lower(a,2)..array_upper(a,2) LOOP -- по столбцам
            RAISE NOTICE 'a[%][%] = %', i, j, a[i][j];
        END LOOP;
    END LOOP;
END
\$\$ LANGUAGE plpgsql;"

c 'Итерация элементов двумерного массива не требует вложенного цикла:'

s 1 "DO \$\$
DECLARE
    a integer[] := ARRAY[
        ARRAY[ 10, 20, 30],
        ARRAY[100,200,300]
    ];
    x integer;
BEGIN
    FOREACH x IN ARRAY a LOOP 
        RAISE NOTICE '%', x;
    END LOOP;
END
\$\$ LANGUAGE plpgsql;"


c 'Существует также возможность выполнять в подобном цикле итерацию по срезам, а не по отдельным элементам. Значение SLICE в такой конструкции должно быть целым числом, не превышающим размерность массива, а переменная, куда читаются срезы, сама должна быть массивом. В примере — цикл по одномерным срезам:'

s 1 "DO \$\$
DECLARE
    a integer[] := ARRAY[
        ARRAY[ 10, 20, 30],
        ARRAY[100,200,300]
    ];
    x integer[];
BEGIN
    FOREACH x SLICE 1 IN ARRAY a LOOP 
        RAISE NOTICE '%', x;
    END LOOP;
END
\$\$ LANGUAGE plpgsql;"

P 8

###############################################################################
h 'Массивы и подпрограммы'

c 'В теме «SQL. Процедуры» мы рассматривали перегрузку и полиморфизм и создали функцию maximum, которая находила максимальное из трех чисел. Обобщим ее на произвольное число аргументов. Для этого объявим один VARIADIC-параметр:'

s 1 "CREATE FUNCTION maximum(VARIADIC a integer[]) RETURNS integer
AS \$\$
DECLARE
    x integer;
    maxsofar integer;
BEGIN
    FOREACH x IN ARRAY a LOOP
        IF x IS NOT NULL AND (maxsofar IS NULL OR x > maxsofar) THEN
            maxsofar := x;
        END IF;
    END LOOP;
    RETURN maxsofar;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

c 'Пробуем:'

s 1 "SELECT maximum(12, 65, 47);"
s 1 "SELECT maximum(12, 65, 47, null, 87, 24);"
s 1 "SELECT maximum(null, null);"

c 'Для полноты картины и эта функция может быть сделана полиморфной, чтобы принимать любой тип данных (для которого, конечно, должны быть определены операции сравнения).'

s 1 "DROP FUNCTION maximum(integer[]);"

ul 'Полиморфные типы anycompatiblearray и anycompatible (а также anyarray и anyelement) всегда согласованы между собой: anycompatiblearray = anycompatible[], anyarray = anyelement[];'
ul 'Нам нужна переменная, имеющая тип элемента массива. Но объявить ее как anycompatible нельзя — она должна иметь реальный тип. Здесь помогает конструкция %TYPE.'

s 1 "CREATE FUNCTION maximum(VARIADIC a anycompatiblearray, maxsofar OUT anycompatible)
AS \$\$
DECLARE
    x maxsofar%TYPE;
BEGIN
    FOREACH x IN ARRAY a LOOP
        IF x IS NOT NULL AND (maxsofar IS NULL OR x > maxsofar) THEN
            maxsofar := x;
        END IF;
    END LOOP;
END
\$\$ IMMUTABLE LANGUAGE plpgsql;"

c 'Проверим:'

s 1 "SELECT maximum(12, 65, 47);"
s 1 "SELECT maximum(12.1, 65.3, 47.6);"
s 1 "SELECT maximum(12, 65.3, 15e2, 3.14);"

c 'Вот теперь у нас получился практически полный аналог выражения greatest!'

P 10

###############################################################################
h 'Массив или таблица?'

c 'Представим себе, что мы проектируем базу данных для ведения блога. В блоге есть сообщения, и нам хотелось бы сопоставлять им теги.'
c 'Традиционный подход состоит в том, что для тегов надо создать отдельную таблицу, например, так:'

s 1 "CREATE TABLE posts(
    post_id integer PRIMARY KEY,
    message text
);"
s 1 "CREATE TABLE tags(
    tag_id integer PRIMARY KEY,
    name text
);"

c 'Связываем сообщения и теги отношением многие ко многим через еще одну таблицу:'

s 1 "CREATE TABLE posts_tags(
    post_id integer REFERENCES posts(post_id),
    tag_id integer REFERENCES tags(tag_id)
);"

c 'Наполним таблицы тестовыми данными:'

s 1 "INSERT INTO posts(post_id,message) VALUES
    (1, 'Перечитывал пейджер, много думал.'),
    (2, 'Это было уже весной и я отнес елку обратно.');"
s 1 "INSERT INTO tags(tag_id,name) VALUES
    (1, 'былое и думы'), (2, 'технологии'), (3, 'семья');"
s 1 "INSERT INTO posts_tags(post_id,tag_id) VALUES
    (1,1), (1,2), (2,1), (2,3);"

c 'Теперь мы можем вывести сообщения и теги:'

s 1 "SELECT p.message, t.name
FROM posts p
     JOIN posts_tags pt ON pt.post_id = p.post_id
     JOIN tags t ON t.tag_id = pt.tag_id
ORDER BY p.post_id, t.name;"

c 'Или чуть иначе — возможно удобнее получить массив тегов. Для этого используем агрегирующую функцию:'

s 1 "SELECT p.message, array_agg(t.name ORDER BY t.name) tags
FROM posts p
     JOIN posts_tags pt ON pt.post_id = p.post_id
     JOIN tags t ON t.tag_id = pt.tag_id
GROUP BY p.post_id
ORDER BY p.post_id;"

c 'Можем найти все сообщения с определенным тегом:'

s 1 "SELECT p.message
FROM posts p
     JOIN posts_tags pt ON pt.post_id = p.post_id
     JOIN tags t ON t.tag_id = pt.tag_id
WHERE t.name = 'былое и думы'
ORDER BY p.post_id;"

c 'Может потребоваться найти все уникальные теги — это совсем просто:'

s 1 "SELECT t.name
FROM tags t
ORDER BY t.name;"

p

c 'Теперь попробуем подойти к задаче по-другому. Пусть теги будут представлены текстовым массивом прямо внутри таблицы сообщений.'

s 1 "DROP TABLE posts_tags;"
s 1 "DROP TABLE tags;"
s 1 "ALTER TABLE posts ADD COLUMN tags text[];"

c 'Теперь у нас нет идентификаторов тегов, но они нам не очень и нужны.'

s 1 "UPDATE posts SET tags = '{\"былое и думы\",\"технологии\"}'
WHERE post_id = 1;"
s 1 "UPDATE posts SET tags = '{\"былое и думы\",\"семья\"}'
WHERE post_id = 2;"

c 'Вывод всех сообщений упростился:'

s 1 "SELECT p.message, p.tags
FROM posts p
ORDER BY p.post_id;"

c 'Сообщения с определенным тегом тоже легко найти (используем оператор пересечения &&).'
c 'Эта операция может быть ускорена с помощью индекса GIN, и для такого запроса не придется перебирать всю таблицу сообщений.'

s 1 "SELECT p.message
FROM posts p
WHERE p.tags && '{\"былое и думы\"}'
ORDER BY p.post_id;"

c 'А вот получить список тегов довольно сложно. Это требует разворачивания всех массивов тегов в большую таблицу и поиск уникальных значений — тяжелая операция.'

s 1 "SELECT DISTINCT unnest(p.tags) AS name
FROM posts p;"

c 'Тут хорошо видно, что имеет место дублирование данных.'

p

c 'Итак, оба подхода вполне могут применяться.'
c 'В простых случаях массивы выглядят проще и работают хорошо.'
c 'В более сложных сценариях (представьте, что вместе с именем тега мы хотим хранить дату его создания; или требуется проверка ограничений целостности) классический вариант становится более привлекательным.'

###############################################################################

stop_here
cleanup
demo_end
