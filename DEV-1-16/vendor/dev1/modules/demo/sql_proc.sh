#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

start_here 4

###############################################################################
h 'Процедуры без параметров'

c 'Начнем с примера простой процедуры без параметров.'

s 1 "CREATE TABLE t(a float);"
s 1 'CREATE PROCEDURE fill()
AS $$
    TRUNCATE t;
    INSERT INTO t SELECT random() FROM generate_series(1,3);
$$ LANGUAGE sql;'

c 'Чтобы вызвать процедуру, необходимо использовать специальный оператор:'

s 1 "CALL fill();"

c 'Результат работы виден в таблице:'

s 1 "SELECT * FROM t;"

c 'А теперь переопределим нашу процедуру в стиле стандарта SQL:'

s 1 "CREATE OR REPLACE PROCEDURE fill()
LANGUAGE sql
BEGIN ATOMIC
    DELETE FROM t;  -- команда TRUNCATE пока что не поддерживается в таких подпрограммах 
    INSERT INTO t SELECT random() FROM generate_series(1,3);
END;"

c 'Убедимся в ее работоспособности:'

s 1 "CALL fill();"
s 1 "SELECT * FROM t;"

c 'И попробуем в процедуре выполнить фиксацию транзакции:'

s 1 "CREATE OR REPLACE PROCEDURE fill()
LANGUAGE sql
BEGIN ATOMIC
    DELETE FROM t;
    INSERT INTO t SELECT random() FROM generate_series(1,3);
    COMMIT;
END;"

#c 'К сожалению, возможности использовать команды COMMIT и ROLLBACK даже для процедур, созданных в новом стиле стандарта SQL, пока что нет.'
c 'Обратите внимание, что мы получили ошибку о недопустимой команде еще на этапе определения подпрограммы.'

c 'Переименуем таблицу, с которой работает наша процедура:'

s 1 "ALTER TABLE t RENAME TO ta;"

c 'Вызов ниже не приведет к ошибке — таблица в определении процедуры в системном каталоге теперь представлена не по имени, а по идентификатору, который был получен еще на этапе создания подпрограммы.'

s 1 "CALL fill();"

p

c 'Ту же самую задачу, что выполняла процедура, можно решить и с помощью функции, возвращаемое значение которой определяется последним оператором. Можно объявить тип результата void, если фактически функция ничего не возвращает, или вернуть что-то осмысленное.'

c 'Возвратим таблице прежнее имя и определим функцию:'

s 1 "ALTER TABLE ta RENAME TO t;"

s 1 'CREATE FUNCTION fill_avg() RETURNS float
LANGUAGE sql
BEGIN ATOMIC
    DELETE FROM t; 
    INSERT INTO t SELECT random() FROM generate_series(1, 3); 
    SELECT avg(a) FROM t; 
END;'

c 'В любом случае функция вызывается в контексте какого-либо выражения:'

s 1 "SELECT fill_avg();"
s 1 "SELECT * FROM t;"

c 'Чего нельзя достичь с помощью функции — это управления транзакциями. Но и в процедурах на языке SQL, как мы видели, это пока не поддерживается (зато поддерживается при использовании других языков).'

p

###############################################################################
h 'Процедуры с параметрами'

c 'Добавим в процедуру входной параметр — число строк:'

s 1 'DROP PROCEDURE fill();'
s 1 'CREATE PROCEDURE fill(nrows integer)
LANGUAGE sql
BEGIN ATOMIC
    DELETE FROM t;
    INSERT INTO t SELECT random() FROM generate_series(1, nrows);
END;'

c 'Точно так же, как и в случае функций, при вызове процедур фактические параметры можно передавать позиционным способом или по имени:'

s 1 'CALL fill(nrows => 5);'
s 1 "SELECT * FROM t;"

c 'Процедуры могут также иметь OUT- и INOUT-параметры, с помощью которых можно возвращать значения:'

s 1 'DROP PROCEDURE fill(integer);'
s 1 'CREATE PROCEDURE fill(IN nrows integer, OUT average float)
LANGUAGE sql
BEGIN ATOMIC
    DELETE FROM t;
    INSERT INTO t SELECT random() FROM generate_series(1, nrows);
    SELECT avg(a) FROM t; -- как в функции
END;'

c 'Попробуем:'

s 1 'CALL fill(5, NULL /* значение не используется, но его необходимо указать*/);'

P 7

###############################################################################
h 'Перегруженные подпрограммы'

c 'Перегрузка работает одинаково и для функций, и для процедур. Они имеют общее пространство имен.'
c 'В качестве примера напишем функцию, возвращающую большее из двух целых чисел. (Похожее выражение есть в SQL и называется greatest, но мы напишем собственную функцию.)'

s 1 'CREATE FUNCTION maximum(a integer, b integer) RETURNS integer
LANGUAGE sql
RETURN CASE WHEN a > b THEN a ELSE b END;'


c 'Проверим:'

s 1 'SELECT maximum(10, 20);'

c 'Допустим, мы решили сделать аналогичную функцию для трех чисел. Благодаря перегрузке, не надо придумывать для нее какое-то новое название:'

s 1 'CREATE FUNCTION maximum(a integer, b integer, c integer)
RETURNS integer
LANGUAGE sql
RETURN CASE
         WHEN a > b THEN maximum(a, c)
         ELSE maximum(b, c)
       END;'


c 'Теперь у нас две функции с одним именем, но разным числом параметров:'

s 1 '\df maximum'

c 'И обе работают:'

s 1 'SELECT maximum(10, 20), maximum(10, 20, 30);'

c 'Команда CREATE OR REPLACE позволяет создать подпрограмму или заменить существующую, не удаляя ее. Поскольку в данном случае функция с такой сигнатурой уже существует, она будет заменена:'

s 1 'CREATE OR REPLACE FUNCTION maximum(a integer, b integer, c integer)
RETURNS integer
LANGUAGE sql
RETURN CASE
         WHEN a > b THEN
           CASE WHEN a > c THEN a ELSE c END
         ELSE
           CASE WHEN b > c THEN b ELSE c END
         END;'


c 'Пусть наша функция работает не только для целых чисел, но и для вещественных. Как этого добиться? Можно определить еще такую функцию:'

s 1 'CREATE FUNCTION maximum(a real, b real) RETURNS real
LANGUAGE sql
RETURN CASE WHEN a > b THEN a ELSE b END;'


c 'Теперь у нас три функции с одинаковым именем:'

s 1 '\df maximum'

c 'Две из них имеют одинаковое количество параметров, но отличаются их типами:'

s 1 'SELECT maximum(10, 20), maximum(1.1, 2.2);'

c 'Если подпрограмма перегружена несколько раз, то для получения информации только о некоторых из них можно указать в команде \df типы интересующих параметров:'

s 1 '\df maximum real'

p

c 'Дальше нам придется определить функции для всех остальных типов данных и повторить все то же самое для трех параметров. Притом что операторы в теле этих функций будут одни и те же.'

p

###############################################################################
h 'Полиморфные функции'

c 'Здесь нам помогут полиморфные типы anyelement и anycompatible. Это псевдотипы, взамен которых при вызове и интерпретации функции будет подставлен тип фактического параметра. Разумеется, в случае определения подпрограммы в стиле стандарта SQL ее код будет разобран еще на этапе создания, и воспользоваться полиморфными псевдотипами не удастся.'

c 'Удалим все три наши функции...'

s 1 'DROP FUNCTION maximum(integer, integer);'
s 1 'DROP FUNCTION maximum(integer, integer, integer);'
s 1 'DROP FUNCTION maximum(real, real);'

c '...и затем создадим новую:'

s 1 'CREATE FUNCTION maximum(a anyelement, b anyelement)
RETURNS anyelement
AS $$
    SELECT CASE WHEN a > b THEN a ELSE b END;
$$ LANGUAGE sql;'

c 'Такая функция должна принимать любой тип данных (а работать будет с любым типом, для которого определен оператор «больше»).'

c 'Получится?'

s 1 "SELECT maximum('A', 'B');"

c 'Увы, нет. В данном случае строковые литералы могут быть типа char, varchar, text — конкретный тип нам неизвестен. Но можно применить явное приведение типов:'

s 1 "SELECT maximum('A'::text, 'B'::text);"

c 'Еще пример с другим типом:'

s 1 "SELECT maximum(now(), now() + interval '1 day');"

c 'Тип результата функции всегда будет тот же, что и тип параметров.'

c 'Но можно продвинуться еще дальше — сделать так, чтобы можно было использовать в полиморфных подпрограммах не абсолютно одинаковые типы, а совместимые, то есть те, что могут быть приведены друг к другу неявно. Для этого нужно использовать полиморфный псевдотип anycompatible.'

c 'Удалим нашу функцию и взамен нее создадим другую:'

s 1 "DROP FUNCTION maximum;"

s 1 "CREATE FUNCTION maximum(a anycompatible, b anycompatible)
RETURNS anycompatible
AS \$\$
    SELECT CASE WHEN a > b THEN a ELSE b END;
\$\$ LANGUAGE sql;"

c 'Повторим наш опыт с параметрами-литералами:'

s 1 "SELECT maximum('A', 'B');"

c 'Получилось!'

c 'Но если типы параметров не совпадают и не могут быть неявно приведены к некоторому общему типу, то будет ошибка:'

s 1 "SELECT maximum(1, 'A');"

c 'В этом примере такое ограничение выглядит естественно, хотя в некоторых случаях оно может оказаться и неудобным.'

p

c 'Определим теперь функцию с тремя параметрами, но так, чтобы третий можно было не указывать:'

s 1 'CREATE FUNCTION maximum(
    a anycompatible, 
    b anycompatible, 
    c anycompatible DEFAULT NULL
) RETURNS anycompatible 
AS $$
SELECT CASE
         WHEN c IS NULL THEN
             x
         ELSE
             CASE WHEN x > c THEN x ELSE c END
       END
FROM (
    SELECT CASE WHEN a > b THEN a ELSE b END
) max2(x);
$$ LANGUAGE sql;'



s 1 'SELECT maximum(10, 11.21, 3e3);'

c 'Так работает. А так?'

s 1 'SELECT maximum(10, 11.21);'

c 'А так произошел конфликт перегруженных функций:'

s 1 '\df maximum'

c 'Невозможно понять, имеем ли мы в виду функцию с двумя параметрами, или с тремя (но просто не указали последний).'

c 'Мы решим этот конфликт просто — удалим первую функцию за ненадобностью.'

s 1 'DROP FUNCTION maximum(anycompatible, anycompatible);'

s 1 'SELECT maximum(10, 11.21), maximum(10, 11.21, 3e3); '

c 'Теперь все работает. А в теме «PL/pgSQL. Массивы» мы узнаем, как определять подпрограммы с произвольным числом параметров.'

###############################################################################

stop_here
cleanup
demo_end
