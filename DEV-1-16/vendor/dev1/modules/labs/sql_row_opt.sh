#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Функция для шестнадцатеричной системы'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Сначала для удобства определим функцию для одной цифры:'

s 1 "CREATE FUNCTION digit(d text) RETURNS integer
IMMUTABLE LANGUAGE sql
RETURN ascii(d) - CASE
         WHEN d BETWEEN '0' AND '9' THEN ascii('0')
         ELSE ascii('A') - 10
       END;"


c 'Теперь основная функция:'

s 1 "CREATE FUNCTION convert(hex text) RETURNS integer
IMMUTABLE LANGUAGE sql
BEGIN ATOMIC
  WITH s(d,ord) AS (
    SELECT *
    FROM regexp_split_to_table(reverse(upper(hex)),'') WITH ORDINALITY
  )
  SELECT sum(digit(d) * 16^(ord-1))::integer FROM s;
END;"


s 1 "SELECT convert('0FE'), convert('0FF'), convert('100');"


###############################################################################
h '2. Функция для любой системы счисления'

c 'Предполагаем, что основание системы счисления от 2 до 36, то есть число записывается цифрами от 0 до 9, либо буквами от A до Z. В этом случае изменения минимальные.'

s 1 "DROP FUNCTION convert(text);"
s 1 "CREATE FUNCTION convert(num text, radix integer DEFAULT 16) RETURNS integer
IMMUTABLE LANGUAGE sql
BEGIN ATOMIC
  WITH s(d,ord) AS (
    SELECT *
    FROM regexp_split_to_table(reverse(upper(num)),'') WITH ORDINALITY
  )
  SELECT sum(digit(d) * radix^(ord-1))::integer FROM s;
END;"

s 1 "SELECT convert('101100', 2), convert('2C'), convert('54', 8);"

c 'Заметим, что в PostgreSQL начиная с версии 16 есть возможность записи целочисленных констант не только в десятичном, но и в двоичном, шестнадцатеричном и восьмеричном виде. Такая возможность закреплена в современном стандарте SQL:'

s 1 "SELECT 0b101100 AS bin, 0x2C AS hex, 0o54 AS oct;"

###############################################################################
h '3. Функция generate_series для строк'

c 'Сначала напишем вспомогательные функции, переводящие строку в числовое представление и обратно.'
c 'Первая очень похожа на функцию из предыдущего задания:'

s 1 "CREATE FUNCTION text2num(s text) RETURNS integer
IMMUTABLE LANGUAGE sql
BEGIN ATOMIC
  WITH s(d,ord) AS (
    SELECT *
    FROM regexp_split_to_table(reverse(s),'') WITH ORDINALITY
  )
  SELECT sum( (ascii(d)-ascii('A')) * 26^(ord-1))::integer FROM s;
END;"

c 'Обратную функцию напишем с помощью рекурсивного запроса:'

s 1 "CREATE FUNCTION num2text(n integer, digits integer) RETURNS text
IMMUTABLE LANGUAGE sql
BEGIN ATOMIC
  WITH RECURSIVE r(num,txt, level) AS (
    SELECT n/26, chr( n%26 + ascii('A') )::text, 1
    UNION ALL
    SELECT r.num/26, chr( r.num%26 + ascii('A') ) || r.txt, r.level+1
    FROM r
    WHERE r.level < digits
  )
  SELECT r.txt FROM r WHERE r.level = digits;
END;"

s 1 "SELECT num2text( text2num('ABC'), length('ABC') );"

c 'Теперь функцию generate_series для строк можно переписать, используя generate_series для целых чисел.'

s 1 "CREATE FUNCTION generate_series(start text, stop text) RETURNS SETOF text
IMMUTABLE LANGUAGE sql
BEGIN ATOMIC
  SELECT num2text( g.n, length(start)) FROM generate_series(text2num(start), text2num(stop)) g(n);
END;"

s 1 "SELECT generate_series('AZ','BC');"

s 1 "\c postgres"
s 1 "DROP DATABASE $TOPIC_DB;"

###############################################################################

stop_here
cleanup
