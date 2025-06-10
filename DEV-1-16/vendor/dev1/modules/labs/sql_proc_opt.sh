#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Перегрузка процедур и функций'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Не получится, так как в сигнатуру подпрограммы входит только имя и тип входных параметров (возвращаемое значение игнорируется), и при этом процедуры и функции имеют общее пространство имен.'

s 1 "CREATE PROCEDURE test(IN x integer)
LANGUAGE sql
RETURN 1;"

s 1 "CREATE FUNCTION test(IN x integer) RETURNS integer
LANGUAGE sql
RETURN 1;"

c 'В некоторых сообщениях, как и в этом, вместо слова «процедура» используется «функция», поскольку во многом они устроены одинаково.'

s 1 "CREATE OR REPLACE PROCEDURE test(IN x integer, OUT y integer)
LANGUAGE sql
RETURN x;"

c 'Такую процедуру тоже создать нельзя, так как уже имеется процедура с такой же сигнатурой, а изменять выходные параметры (и факт их наличия) для имеющейся подпрограммы также запрещено. Нам предлагают удалить подпрограмму, чтобы затем создать ее заново.'

###############################################################################
h '2. Нормализация данных'

c 'Таблица с тестовыми данными:'

s 1 "CREATE TABLE samples(a float);"
s 1 "INSERT INTO samples(a)
    SELECT (0.5 - random())*100 FROM generate_series(1,10);"

c 'Процедуру можно написать, используя один SQL-оператор:'

s 1 "CREATE PROCEDURE normalize_samples(INOUT coeff float)
LANGUAGE sql
BEGIN ATOMIC
   WITH c(coeff) AS (
       SELECT 1/max(abs(a))
       FROM samples
   ),
   upd AS (
       UPDATE samples
       SET a = a * c.coeff
       FROM c
   )
   SELECT coeff FROM c;
END;"

s 1 "CALL normalize_samples(NULL);"
s 1 "SELECT * FROM samples;"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
