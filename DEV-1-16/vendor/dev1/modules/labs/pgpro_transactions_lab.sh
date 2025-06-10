#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Взаимоблокировка в автономной транзакции'

c "Создадим базу данных:"
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE TABLE t1 AS SELECT 1 n;"

c "Начинаем транзакцию и блокируем строку:"
s 1 "BEGIN;"
s 1 "UPDATE t1 SET n=2;"

c "Пытаемся блокировать ту же строку в автономной транзакции и получаем ошибку:"
s 1 "BEGIN AUTONOMOUS;"
s 1 "UPDATE t1 SET n=3;"
s 1 "END AUTONOMOUS;"

c "Основную транзакцию можно зафиксировать:"
s 1 "COMMIT;"

###############################################################################
h '2. Аудит: dblink и автономные транзакции'

c 'Тестовая таблица:'
s 1 "CREATE TABLE test(n int);"

c 'Таблица для аудита:'
s 1 "CREATE TABLE test_audit(
  time timestamptz,
  username text,
  operation text
);"

c 'Первый вариант триггерной функции использует расширение dblink:'
s 1 "CREATE EXTENSION dblink;"
s 1 "CREATE OR REPLACE FUNCTION test_audit() RETURNS trigger AS \$$
BEGIN
  PERFORM dblink(
    'dbname='||current_database(),
    'INSERT INTO test_audit VALUES (now(), current_user, '''||tg_op||''')'
  );
  RETURN new;
END;
\$$ LANGUAGE plpgsql;"

c 'Триггер:'
s 1 "CREATE TRIGGER test_audit
AFTER INSERT OR UPDATE OR DELETE
ON test
FOR EACH ROW
EXECUTE FUNCTION test_audit();
"

c 'Замеряем время.'
s 1 "\timing on"
s 1 "INSERT INTO test SELECT g.s FROM generate_series(1,500) AS g(s);"
s 1 "\timing off"

c 'Опустошим обе таблицы и заменим триггерную функцию на вариант, использующий автономную транзакцию.'
s 1 "TRUNCATE test;"
s 1 "TRUNCATE test_audit;"

s 1 'CREATE OR REPLACE FUNCTION test_audit() RETURNS trigger AS $$
BEGIN AUTONOMOUS
  INSERT INTO test_audit VALUES (now(), current_user, tg_op);
  RETURN new;
END;
$$ LANGUAGE plpgsql;'

c 'Еще раз замеряем время.'
s 1 "\timing on"
s 1 "INSERT INTO test SELECT g.s FROM generate_series(1,500) AS g(s);"
s 1 "\timing off"

c 'Автономные транзакции работают быстрее, поскольку нет накладных расходов на установку соединения.'

###############################################################################
h '3. Временные таблицы и пул соединений'

c 'Включим пул соединений, выделив один процесс для каждой базы данных. Транзакции сеансов будут использовать его по очереди:'
s 1 "ALTER SYSTEM SET session_pool_size=1;"
pgctl_restart A
psql_open A 1
psql_open A 2

c 'В каждом из двух сеансов создадим временную таблицу.'
s 1 "CREATE TEMP TABLE temp (
  session int DEFAULT 1,
  pid int DEFAULT pg_backend_pid()
);"
s 2 "CREATE TEMP TABLE temp (
  session int DEFAULT 2,
  pid int DEFAULT pg_backend_pid()
);"

c 'Теперь пусть сеансы по очереди вставляют строки в таблицы.'
insert="INSERT INTO temp SELECT;"
s 1 $insert
s 2 $insert
s 1 $insert
s 2 $insert

c 'Вот содержимое временных таблиц:'
select="SELECT * FROM temp;"
s 1 $select
s 2 $select

c 'Встроенный пул соединений Postgres Pro Enterprise сохраняет временные таблицы уровня сеанса. При использовании сторонних менеджеров пула сохранение контекста сеанса не гарантируется.'

########################################################################

stop_here
cleanup
