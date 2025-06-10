#!/bin/bash

. ../lib

init

psql_open A 2

start_here

###############################################################################
h '1. Снимки данных двух транзакций'

c 'Таблица с одной строкой:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
export PID1=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")

s 1 'CREATE TABLE t(n integer);'

s 1 "BEGIN;"
s 1 "INSERT INTO t(n) VALUES (1);"
s 1 'SELECT pg_current_xact_id();'

export T0=$(s_bare 1 "SELECT backend_xid FROM pg_stat_activity WHERE pid = $PID1;")

s 1 "COMMIT;"

c 'Первая транзакция видит строку:'

s 1 'BEGIN ISOLATION LEVEL REPEATABLE READ;'
s 1 'SELECT * FROM t;'
s 1 'SELECT pg_current_xact_id();'
s 1 'SELECT pg_current_snapshot();'

export T1=$(s_bare 1 "SELECT backend_xid FROM pg_stat_activity WHERE pid = $PID1;")

c 'Вторая транзакция в другом сеансе удаляет строку:'

s 2 "\c $TOPIC_DB"
export PID2=$(s_bare 1 "SELECT pid FROM pg_stat_activity WHERE datname = '$TOPIC_DB' ORDER BY backend_start DESC LIMIT 1;")

s 2 'BEGIN ISOLATION LEVEL REPEATABLE READ;'
s 2 'DELETE FROM t;'
s 2 'SELECT * FROM t;'
s 2 'SELECT pg_current_xact_id();'
s 2 'SELECT pg_current_snapshot();'

export T2=$(s_bare 1 "SELECT backend_xid FROM pg_stat_activity WHERE pid = $PID2;")

c 'Первая транзакция продолжает видеть строку:'

s 1 'SELECT xmin, xmax, * FROM t;'

c 'Снимки обеих транзакций одинаковы, и по правилам видимости они обе должны были бы видеть строку, так как'
ul "изменения транзакции xmin = $T0 видны в снимке ($T0 < $T1),"
ul "изменения транзакции xmax = $T2 не видны в снимке ($T2 > $T1)."

c 'Однако вторая транзакция все-таки не видит строку, поскольку она сама ее удалила, а это — исключение из обычных правил видимости.'

s 1 "COMMIT;"
s 2 "COMMIT;"

###############################################################################
h '2. Снимок вложенного запроса'

c 'Внутри функции, подсчитывающей число строк таблицы, вставим односекундную задержку для удобства тестирования:'

s 1 "CREATE FUNCTION test() RETURNS bigint
VOLATILE LANGUAGE sql
BEGIN ATOMIC
  SELECT pg_sleep(1);
  SELECT count(*) FROM t;
END;"

c 'Теперь начинаем транзакцию с уровнем изоляции Read Committed и в запросе несколько раз вызываем функцию, одновременно подсчитывая количество строк подзапросом.'

s 1 "BEGIN ISOLATION LEVEL READ COMMITTED;"
ss 1 "SELECT (SELECT count(*) FROM t) AS cnt, test()
FROM generate_series(1,5);"

c 'Параллельно выполняем другую транзакцию, которая увеличивает число строк в таблице. Если основной запрос и вложенный запрос используют разные снимки, мы обнаружим это по разнице в результате.'

sleep 2

si 2 "INSERT INTO t VALUES (1);"

r 1
s 1 "END;"

c 'Значение первого столбца не изменяется — запрос использует снимок, созданный в начале выполнения. Однако значение во втором столбце изменяется — запросы внутри volatile-функции используют отдельные снимки.'

c 'Повторим эксперимент для уровня изоляции Repeatable Read:'

s 1 "TRUNCATE t;"

s 1 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
ss 1 "SELECT (SELECT count(*) FROM t) AS cnt, test()
FROM generate_series(1,5);"

sleep 2

si 2 "INSERT INTO t VALUES (1);"

r 1
s 1 "END;"

c 'Теперь еще раз то же самое для функции с категорией изменчивости stable.'

s 1 "ALTER FUNCTION test STABLE;"

c 'Уровень Read Committed:'

s 1 "TRUNCATE t;"

s 1 "BEGIN ISOLATION LEVEL READ COMMITTED;"
ss 1 "SELECT (SELECT count(*) FROM t) AS cnt, test()
FROM generate_series(1,5);"

sleep 2

si 2 "INSERT INTO t VALUES (1);"

r 1
s 1 "END;"

c 'Уровень Repeatable Read:'

s 1 "TRUNCATE t;"

s 1 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
ss 1 "SELECT (SELECT count(*) FROM t) AS cnt, test()
FROM generate_series(1,5);"

sleep 2

si 2 "INSERT INTO t VALUES (1);"

r 1
s 1 "END;"

c 'Выводы:'
ul 'Запросы в volatile-функциях на уровне изоляции Read Committed используют собственные снимки и могут видеть изменения в процессе работы оператора. Такая возможность скорее опасна, чем полезна.'
ul 'При любых других комбинациях категории изменчивости и уровня изоляции вложенные запросы используют снимок основного запроса.'

###############################################################################
h '3. Экспорт снимка'

c 'Функция pg_export_snapshot возвращает идентификатор снимка, который можно передать в другую транзакцию (внешними по отношению к СУБД средствами):'

s 1 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
s 1 "SELECT count(*) FROM t;"

s 1 "SELECT pg_export_snapshot();"
EXPSNAPSHOT=$(echo $RESULT | head -n 3 | tail -n 1 | xargs)

c 'В другом сеансе удаляем все строки из таблицы:'

s 2 "DELETE FROM t;"

c 'Затем транзакция импортирует снимок и видит в нем те же данные, которые доступны транзакции, которая экспортировала этот снимок:'

s 2 "BEGIN ISOLATION LEVEL REPEATABLE READ;"
s 2 "SET TRANSACTION SNAPSHOT '$EXPSNAPSHOT';"
s 2 "SELECT count(*) FROM t;"
s 2 "COMMIT;"

s 1 "COMMIT;"

###############################################################################

stop_here
cleanup
