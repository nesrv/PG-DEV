#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
psql_open A 2
s 2 "\c $TOPIC_DB"

start_here 5

###############################################################################
h 'Управление транзакциями'

c 'По умолчанию psql работает в режиме автофиксации:'

s 1 '\echo :AUTOCOMMIT'

c 'Это приводит к тому, что любая одиночная команда, выданная без явного указания начала транзакции, сразу же фиксируется.'

ul 'Проверьте, включен ли аналогичный режим в драйвере PostgreSQL вашего любимого языка программирования?'

c 'Создадим таблицу с одной строкой:'

s 1 "CREATE TABLE t(
  id integer,
  s text
);"
s 1 "INSERT INTO t(id, s) VALUES (1, 'foo');"

c 'Увидит ли таблицу и строку другая транзакция?'

s 2 "SELECT * FROM t;"

c 'Да. Сравните:'

s 1 "BEGIN; -- явно начинаем транзакцию"
s 1 "INSERT INTO t(id, s) VALUES (2, 'bar');"

c 'Что увидит другая транзакция на этот раз?'

s 2 "SELECT * FROM t;"

c 'Изменения еще не зафиксированы, поэтому не видны другой транзакции.'

s 1 "COMMIT;"

c 'А теперь?'

s 2 "SELECT * FROM t;"

c 'Режим без автофиксации неявно начинает транзакцию при первой выданной команде; изменения надо фиксировать самостоятельно.'

s 1 '\set AUTOCOMMIT off'

s 1 "INSERT INTO t(id, s) VALUES (3, 'baz');"

c 'Что на этот раз?'

s 2 "SELECT * FROM t;"

c 'Изменения не видны; транзакция была начата неявно.'

s 1 "COMMIT;"

c 'Ну и наконец:'

s 2 "SELECT * FROM t;"

c 'Восстановим режим, в котором psql работает по умолчанию.'

s 1 '\set AUTOCOMMIT on'

p

c 'Отдельные изменения можно откатывать, не прерывая транзакцию целиком (хотя необходимость в этом возникает нечасто).'

s 1 'BEGIN;'
s 1 'SAVEPOINT sp; -- точка сохранения'
s 1 "INSERT INTO t(id, s) VALUES (4, 'qux');"
s 1 "SELECT * FROM t;"

c 'Обратите внимание: свои собственные изменения транзакция видит, даже если они не зафиксированы.'
c 'Теперь откатим все до точки сохранения.'
c 'Откат к точке сохранения не подразумевает передачу управления (то есть не работает как GOTO); отменяются только те изменения состояния БД, которые были выполнены от момента установки точки до текущего момента.'

s 1 'ROLLBACK TO sp;'

c 'Что увидим?'

s 1 "SELECT * FROM t;"

c 'Сейчас изменения отменены, но транзакция продолжается:'

s 1 "INSERT INTO t(id, s) VALUES (4, 'xyz');"
s 1 'COMMIT;'

s 1 "SELECT * FROM t;"

P 8

###############################################################################
h 'Подготовленные операторы'

c 'В SQL оператор подготавливается командой PREPARE (эта команда является расширением PostgreSQL, она отсутствует в стандарте):'

s 1 'PREPARE q(integer) AS
  SELECT * FROM t WHERE id = $1;'

c 'При этом выполняются разбор и переписывание, и полученное дерево разбора запоминается.'
c 'После подготовки оператор можно вызывать по имени, передавая фактические параметры:'

s 1 "EXECUTE q(1);"

c 'Если у запроса нет параметров, при подготовке запоминается и построенный план выполнения. Если же параметры есть, как в этом примере, то их фактические значения принимаются во внимание при планировании. Планировщик может счесть, что план, построенный без учета параметров, окажется не хуже, и тогда перестанет выполнять планирование повторно.'

ul 'А как подготовить и выполнить оператор в вашем любимом языке?'
ul 'Есть ли возможность выполнить оператор, НЕ подготавливая его?'

c 'Все подготовленные операторы текущего сеанса можно увидеть в представлении:'

s 1 "SELECT * FROM pg_prepared_statements \gx"

P 10

###############################################################################
h 'Курсоры'

c 'При выполнении команды SELECT сервер передает, а клиент получает сразу все строки:'

s 1 'SELECT * FROM t ORDER BY id;'

c 'Курсор позволяет получать данные построчно.'

s 1 'BEGIN;'
s 1 'DECLARE c CURSOR FOR
  SELECT * FROM t ORDER BY id;'
s 1 'FETCH c;'

c 'Размер выборки можно указывать:'

s 1 'FETCH 2 c;'

c 'Этот размер играет важную роль, когда строк очень много: обрабатывать большой объем данных построчно крайне неэффективно.'

c 'Что, если в процессе чтения мы дойдем до конца таблицы?'

s 1 'FETCH 2 c;'
s 1 'FETCH 2 c;'

c 'FETCH просто перестанет возвращать строки. В обычных языках программирования всегда есть возможность проверить это условие.'

ul 'Как в вашем языке программирования получать данные построчно с помощью курсора?'
ul 'Есть ли возможность НЕ пользоваться курсором и получить все строки сразу?'
ul 'Как настраивается размер выборки для курсора?'

c 'По окончании работы открытый курсор закрывают, освобождая ресурсы:'

s 1 'CLOSE c;'

c 'Однако курсоры автоматически закрываются по завершению транзакции, так что можно не закрывать их явно. (Исключение составляют курсоры, открытые с указанием WITH HOLD.)'

s 1 'COMMIT;'

###############################################################################

stop_here
cleanup
demo_end
