#!/bin/bash

. ../lib

init

start_here 4

###############################################################################
h 'Методы доступа'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'В версии 16 имеется единственный встроенный табличный метод доступа:'

s 1 "SELECT amname FROM pg_am WHERE amtype = 't';"

c 'Зато много различных индексных методов доступа:'

s 1 "SELECT amname FROM pg_am WHERE amtype = 'i';"

c 'С btree знакомы все — это «обычный» метод доступа на основе B-дерева, который используется по умолчанию и покрывает большинство потребностей. Остальные методы доступа также очень полезны, но в специальных ситуациях. Некоторые из них мы рассмотрим позже.'

c 'Для получения информации мы делали запросы к таблицам системного каталога, однако в арсенале psql есть удобная команда, позволяющая получить информацию о методах доступа,
классах и семействах операторов, ей дальше мы и будем пользоваться:'

s 1 '\dA'

P 6

###############################################################################
h 'Классы операторов'

c 'Посмотрим, какие классы операторов определены для B-дерева и для разных типов данных. Для целых чисел:'

s 1 '\dAc btree (smallint|integer|bigint)'

c 'Для удобства такие «похожие по смыслу» классы операторов объединяются в семейства операторов:'

s 1 '\dAf btree (smallint|integer|bigint)'

c 'Семейства операторов позволяют планировщику работать с выражениями разных (но «похожих») типов, даже если они не приведены к одному общему.'

p

c 'Вот классы операторов для типа text (если для одного типа есть несколько классов операторов, то один будет помечен для использования по умолчанию):'

s 1 '\dAc btree text'

ul 'Классы операторов pattern_ops отличаются от обычных тем, что сравнивают строки посимвольно, игнорируя правила сортировки (collation).'

p

c 'А так можно посмотреть, какие операторы включены в конкретный класс операторов:'

s 1 '\dAo btree bool_ops'

p

c 'Метод доступа — это тип индекса, а собственно индекс — это конкретная структура, созданная на основе метода доступа, в которой для каждого столбца используется свой класс операторов.'

c 'Пусть имеется какая-нибудь таблица:'

s 1 "CREATE TABLE t(
    id integer GENERATED ALWAYS AS IDENTITY,
    s text
);"
s 1 "INSERT INTO t(s) VALUES ('foo'), ('bar'), ('xy'), ('z');"

c 'Привычная команда создания индекса выглядит так:'

s_fake 1 "CREATE INDEX ON t(id, s);"

c 'Но это просто сокращение для:'

s 1 "CREATE INDEX ON t
USING btree -- метод доступа
(
    id int4_ops, -- класс операторов для integer
    s  text_ops  -- класс операторов по умолчанию для text
);"

P 8

###############################################################################
h 'Класс операторов для B-дерева'

c 'Класс операторов для B-дерева определяет, как именно будут сортироваться значения в индексе. Для этого он включает пять операторов сравнения, как мы уже видели на примере bool_ops.'

c 'Определим перечислимый тип для единиц измерения информации:'

s 1 "CREATE TYPE capacity_units AS ENUM (
    'B', 'kB', 'MB', 'GB', 'TB', 'PB'
);"

c 'И объявим составной тип данных для представления объема информации:'

s 1 "CREATE TYPE capacity AS (
    amount integer,
    unit capacity_units
);"

c 'Используем новый тип в таблице, которую заполним случайными значениями.'

s 1 "CREATE TABLE test (
    cap capacity
);"
s 1 "INSERT INTO test
    SELECT ( (random()*1023)::integer, u.unit )::capacity
    FROM generate_series(1,100),
         unnest(enum_range(NULL::capacity_units)) AS u(unit);"

c 'По умолчанию значения составного типа сортируются в лексикографическом порядке, но этот порядок не совпадает с естественным порядком:'

s 1 "SELECT * FROM test ORDER BY cap LIMIT 10;"

p

c 'Чтобы исправить сортировку, создадим класс операторов. Начнем с функции, которая пересчитает объем в байты.'

s 1 "CREATE FUNCTION capacity_to_bytes(a capacity) RETURNS numeric
LANGUAGE sql STRICT IMMUTABLE
RETURN a.amount::numeric * 
    1024::numeric ^ ( array_position(enum_range(a.unit), a.unit)-1 );"

c 'Помимо операторов сравнения нам понадобится еще одна вспомогательная функция — тоже для сравнения. Она должна возвращать:'
ul '−1, если первый аргумент меньше второго;'
ul '0, если аргументы равны;'
ul '1, если первый аргумент больше второго.'

s 1 "CREATE FUNCTION capacity_cmp(a capacity, b capacity) RETURNS integer
LANGUAGE sql STRICT IMMUTABLE
RETURN CASE
    WHEN capacity_to_bytes(a) < capacity_to_bytes(b) THEN -1
    WHEN capacity_to_bytes(a) > capacity_to_bytes(b) THEN 1
    ELSE 0
END;"

c 'С помощью этой функции мы определим пять операторов сравнения (и функции для них). Начнем с «меньше»:'

s 1 "CREATE FUNCTION capacity_lt(a capacity, b capacity) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN capacity_cmp(a,b) < 0;"

s 1 "CREATE OPERATOR <(
    LEFTARG = capacity,
    RIGHTARG = capacity,
    FUNCTION = capacity_lt
);"

c 'И аналогично остальные четыре.'

s 1 "CREATE FUNCTION capacity_le(a capacity, b capacity) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN capacity_cmp(a,b) <= 0;"

s 1 "CREATE OPERATOR <=(
    LEFTARG = capacity,
    RIGHTARG = capacity,
    FUNCTION = capacity_le
);"

s 1 "CREATE FUNCTION capacity_eq(a capacity, b capacity) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN capacity_cmp(a,b) = 0;"

s 1 "CREATE OPERATOR =(
    LEFTARG = capacity,
    RIGHTARG = capacity,
    FUNCTION = capacity_eq
);"

s 1 "CREATE FUNCTION capacity_ge(a capacity, b capacity) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN capacity_cmp(a,b) >= 0;"

s 1 "CREATE OPERATOR >=(
    LEFTARG = capacity,
    RIGHTARG = capacity,
    FUNCTION = capacity_ge
);"

s 1 "CREATE FUNCTION capacity_gt(a capacity, b capacity) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT
RETURN capacity_cmp(a,b) > 0;"

s 1 "CREATE OPERATOR >(
    LEFTARG = capacity,
    RIGHTARG = capacity,
    FUNCTION = capacity_gt
);"

c 'Готово. Мы уже можем правильно сравнивать объемы:'

s 1 "SELECT (1,'MB')::capacity > (512, 'kB')::capacity;"

p

c 'Чтобы значения были правильно упорядочены при выборке, нам осталось создать класс операторов. За каждым оператором закреплен собственный номер (в случае btree: 1 — «меньше» и т. д.), поэтому имена операторов могут быть любыми.'

s 1 "CREATE OPERATOR CLASS capacity_ops
DEFAULT FOR TYPE capacity
USING btree AS
    OPERATOR 1 <,
    OPERATOR 2 <=,
    OPERATOR 3 =,
    OPERATOR 4 >=,
    OPERATOR 5 >,
    FUNCTION 1 capacity_cmp(capacity,capacity);"

s 1 "SELECT * FROM test ORDER BY cap LIMIT 10;"

c 'Теперь значения отсортированы правильно.'

p

c 'Наш класс операторов будет использоваться по умолчанию при создании индекса:'

s 1 "CREATE INDEX ON test(cap);"

c 'Любой индекс в PostgreSQL может использоваться только для выражений вида:'
s_fake 1 "<индексированное-поле>  <оператор>  <выражение>"
c 'Причем оператор должен входить в соответствующий класс операторов.'

c 'Будет ли использоваться созданный индекс в таком запросе?'

s 1 'SET enable_seqscan = off;  -- временно отключим последовательное сканирование'

s 1 "EXPLAIN (costs off)
SELECT * FROM test WHERE cap < (100,'B')::capacity;"

c 'Да, поскольку:'
ul 'поле test.cap проиндексировано с помощью метода доступа btree и класса операторов capacity_ops;'
ul 'оператор < входит в класс операторов capacity_ops.'

c 'Поэтому и при доступе с помощью индекса значения будут возвращаться в правильном порядке:'

s 1 "SELECT * FROM test WHERE cap < (100,'B')::capacity ORDER BY cap;"

P 12

###############################################################################
h 'Метод доступа GiST'

c 'Какие именно операторы поддерживает GiST-индекс, существенно зависит от класса операторов. Информацию можно получить как из документации, так и из системного каталога. Возьмем, например, тип данных point (точки).'

c 'Доступный класс операторов:'

s 1 '\dAc gist point'

c 'Операторы в этом классе:'

s 1 '\dAo gist point_ops'

c 'В частности, оператор <@ проверяет, принадлежит ли точка одной из геометрических фигур.'

p

c 'Создадим таблицу со случайными точками:'

s 1 "CREATE TABLE points (
    p point
);"
s 1 "INSERT INTO points(p)
    SELECT point(1 - random()*2, 1 - random()*2)
    FROM generate_series(1,10_000);"

c 'Сколько точек расположено в круге радиуса 0.1?'

s 1 "SELECT count(*) FROM points WHERE p <@ circle '((0,0),0.1)';"

c 'Как выполняется такой запрос?'

s 1 "EXPLAIN (costs off)
SELECT * FROM points WHERE p <@ circle '((0,0),0.1)';"

c 'Полным перебором всей таблицы.'
c 'Создание GiST-индекса позволит ускорить эту операцию. Класс операторов можно не указывать, он один.'

s 1 "CREATE INDEX ON points USING gist(p);"

s 1 "EXPLAIN (costs off)
SELECT * FROM points WHERE p <@ circle '((0,0),0.1)';"

p

c 'Еще один интересный оператор <-> вычисляет расстояние от одной точки до другой. Его можно использовать, чтобы найти точки, ближайшие к данной (так называемый поиск ближайших соседей, k-NN search):'

s 1 "SELECT * FROM points ORDER BY p <-> point '(0,0)' LIMIT 5;"

c 'Эта операция (весьма непростая, если реализовывать ее в приложении) также ускоряется индексом:'

s 1 "EXPLAIN (costs off)
SELECT * FROM points ORDER BY p <-> point '(0,0)' LIMIT 5;"

p

c 'GiST-индекс можно построить и для столбца диапазонного типа:'

s 1 '\dAo gist range_ops'

c 'Здесь мы видим другой набор операторов.'

p

c 'Одно из применений GiST-индекса — поддержка ограничений целостности типа EXCLUDE (ограничения исключения).'

c 'Возьмем классический пример бронирования аудиторий:'

s 1 "CREATE TABLE booking (
    during tstzrange NOT NULL
);"

c 'Ограничение целостности можно сформулировать так: нельзя, чтобы в разных строках таблицы были два пересекающихся (оператор &&) диапазона. Такое ограничение можно задать декларативно на уровне базы данных:'

s 1 "ALTER TABLE booking ADD CONSTRAINT no_intersect
    EXCLUDE USING gist(during WITH &&);"

c 'Проверим:'

s 1 "INSERT INTO booking(during)
    VALUES ('[today 12:00,today 14:00)'::tstzrange);"
s 1 "INSERT INTO booking(during)
    VALUES ('[today 13:00,today 16:00)'::tstzrange);"

c 'Частая ситуация — наличие дополнительного условия в таком ограничении целостности. Добавим номер аудитории:'

s 1 "ALTER TABLE booking ADD room integer NOT NULL DEFAULT 1;"

c 'Но мы не сможем добавить этот столбец в ограничение целостности, поскольку класс операторов для метода gist и типа integer не определен.'

s 1 "ALTER TABLE booking DROP CONSTRAINT no_intersect;"
s 1 "ALTER TABLE booking ADD CONSTRAINT no_intersect
    EXCLUDE USING gist(during WITH &&, room WITH =);"

c 'В этом случае поможет расширение btree_gist, которое добавляет классы операторов для типов данных, которые обычно индексируются с помощью B-деревьев:'

s 1 "CREATE EXTENSION btree_gist;"
s 1 "ALTER TABLE booking ADD CONSTRAINT no_intersect
    EXCLUDE USING gist(during WITH &&, room WITH =);"

c 'Теперь разные аудитории можно бронировать на одно время:'

s 1 "INSERT INTO booking(room, during)
    VALUES (2, '[today 13:00,today 16:00)'::tstzrange);"

c 'Но одну и ту же — нельзя:'

s 1 "INSERT INTO booking(room, during)
    VALUES (1, '[today 13:00,today 16:00)'::tstzrange);"

###############################################################################

stop_here
cleanup
demo_end
