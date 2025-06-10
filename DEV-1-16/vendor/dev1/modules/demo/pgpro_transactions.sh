#!/bin/bash

. ../lib
init

start_here 7

###############################################################################
h 'Структура страниц'

c 'Чтобы заглянуть в страницы, воспользуемся расширением pageinspect.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"
s 1 "CREATE EXTENSION pageinspect;"

c 'В тестовой таблице будет две страницы по две версии строки в каждой.'

s 1 "CREATE TABLE test(s CHAR(300)) WITH (fillfactor=10);"
s 1 "INSERT INTO test SELECT g.n FROM generate_series(1,4) AS g(n);"

c 'Значения xmin и xmax в заголовках версий строк:'

s 1 "SELECT ctid, xmin, xmax FROM test;"

c 'В конце каждой страницы данных находится специальная область размером 24 байта:'

s 1 "SELECT p.page, h.lower, h.upper, h.special, h.pagesize
FROM
  (VALUES(0),(1)) p(page),
  page_header(get_raw_page('test', p.page)) h
;"

c 'В специальной области хранится базовое значение xid, а в заголовках версий строк — 32-битные смещения:'

s 1 "SELECT p.page, substr(f,length(f)-23,8) xid_base
FROM
  (VALUES(0),(1)) p(page),
  get_raw_page('test', p.page) f;
"

c 'Текущее значение счетчика транзакций:'
declare xid=$(s_bare 1 "SELECT pg_current_xact_id();")
s_fake 1 "SELECT pg_current_xact_id();"
r_fake 1 $xid
xid=`echo $xid | tail -2 | head -1`

c 'Пусть теперь сервер выполнит 2^32 транзакций. Выполнение такого количества транзакций работающим сервером заняло бы очень много времени, поэтому остановим его и воспользуемся утилитой pg_resetwal, чтобы поменять текущее значение счетчика.'

pgctl_stop A

eu postgres "${BINPATH}pg_resetwal -x $((${xid}+2**32)) -D ${PGDATA_A}"

# Чтобы сервер стартовал, нужен пустой 16-мегабайтный файл в pg_xact со статусом
# транзакции, которая указана как Latest checkpoint's NextXID в pg_control.
declare nextxid=$(printf %016x $((`sudo ${BINPATH}pg_controldata -D ${PGDATA_A} | grep NextXID | grep -Eo [0-9]+`/1024)))
declare xactfile=$(printf %s  ${nextxid::-4})
e "sudo -u postgres truncate ${PGDATA_A}/pg_xact/${xactfile} --size=16M"

pgctl_start A

c "Иногда после изменения счетчика сервер не запускается из-за отсутствия файла статуса транзакции. В этом случае в журнале появляется сообщение с именем отсутствующего файла, нужно создать пустой файл размером 16 Мбайт в каталоге $PGDATA_A/xact и повторить попытку запуска."

p

psql_open A 1 $TOPIC_DB

s 1 "SELECT pg_current_xact_id();"

c 'Внимание! Не рекомендуется применять утилиту pg_resetwal в производственной среде, поскольку она изменяет внутренние структуры данных и есть опасность потери информации.'

p

c 'Теперь изменим одну строку таблицы.'

s 1 "UPDATE test SET s = '10' WHERE s = '1';"

c 'При этом сервер запишет номер текущей транзакции в поле xmax старой версии строки и в поле xmin новой версии, которая будет размещена в нулевой странице.'
c 'Поскольку номер текущей транзакции отличается от значений xmin в существующих версиях более чем на 2^32, сервер увеличит базовый xid и выполнит локальную заморозку в нулевой странице: выставит в заголовках версий соответствующий флаг, а в поле xmin запишет специальное значение 2. В странице 1 заморозка не делается:'

s 1 "SELECT (page,lp) ctid,t_xmin,t_xmax,f.combined_flags
FROM
  (VALUES(0),(1)) p(page),
  heap_page_items(get_raw_page('test', p.page)),
  heap_tuple_infomask_flags(t_infomask, t_infomask2) f
;
"

c 'Базовый номер xid изменился только в нулевой странице:'

s 1 "SELECT p.page, substr(f,length(f)-23,8) xid_base
FROM
  (VALUES(0),(1)) p(page),
  get_raw_page('test', p.page) f;
"

P 9
##############################################################################
h 'Автономные транзакции'

c 'Автономная транзакция — это независимая транзакция, которая запускается внутри родительской, а фиксируется (или отменяется) до завершения родительской.'
s_fake 1 "
BEGIN;
  команды ...
  BEGIN AUTONOMOUS [ISOLATION LEVEL ...];
    команды ...
  COMMIT [AUTONOMOUS];  -- или ROLLBACK
  команды ...
COMMIT;    -- или ROLLBACK
"

c 'В начале автономной транзакции основная транзакция приостанавливается, и последующие изменения данных относятся к дочерней автономной транзакции. По завершении автономной, родительская транзакция продолжает работу.'
c 'В отличие от вложенной транзакции, которая возникает в обычном PostgreSQL при выполнении команды SAVEPOINT (и, возможно, ROLLBACK TO), результат автономной транзакции не зависит от исхода родительской.'
c 'Автономная транзакция может включать в себя другие автономные транзакции, однако транзакция верхнего уровня не может быть автономной.'

p

c 'В PL/pgSQL есть дополнительная конструкция, в этом случае операторы блока выполняются в отдельной автономной транзакции:'
s_fake 1 "
BEGIN AUTONOMOUS
  операторы ...
END;
"

c 'По сути, такая запись — это просто сокращение для'
s_fake 1 "
BEGIN
  BEGIN AUTONOMOUS;
    операторы ...
  COMMIT;
END;
"

c 'Ошибка в блоке с автономной транзакцией приводит к ее откату, после чего обрабатывается в секции EXCEPTION или передается в вызывающий блок.'

p

c 'В PL/Python есть метод, позволяющий выполнить SQL в автономной транзакции:'

s_fake 1 "with plpy.autonomous():
  plpy.execute(...)"

P 12
##############################################################################

h 'Использование автономных транзакций'

c 'Обычно автономные транзакции используются для аудита, когда нужно сохранить информацию о событии, произошедшем в родительской транзакции, независимо от ее исхода.'

c 'Опустошим таблицу:'
s 1 "TRUNCATE test;"

c 'Мы хотим записывать в таблицу test_audit информацию обо всех изменениях таблицы test, в том числе и о тех, которые не были зафиксированы.'
s 1 "CREATE TABLE test_audit(
  time timestamptz,
  username text,
  operation text
);"

c 'Для этого понадобятся триггер и триггерная функция, тело которой выполняется в автономной транзакции.'
s 1 'CREATE FUNCTION test_audit() RETURNS trigger AS $$
BEGIN AUTONOMOUS
  INSERT INTO test_audit VALUES (now(), current_user, tg_op);
  RETURN new;
END;
$$ LANGUAGE plpgsql;'

s 1 "CREATE TRIGGER test_audit
AFTER INSERT OR UPDATE OR DELETE
ON test
FOR EACH ROW
EXECUTE FUNCTION test_audit();
"

c 'Теперь информация об изменениях будет сохраняться в таблице test_audit, даже если транзакция впоследствии обрывается.'
s 1 "BEGIN;"
s 1 "INSERT INTO test VALUES ('value1'),('value2');"
s 1 "UPDATE test SET s = 'value3';"
s 1 "DELETE FROM test;"

c 'Откатим транзакцию:'
s 1 "ROLLBACK;"

c 'В таблице ничего не осталось:'
s 1 "SELECT * FROM test;"

s 1 "SELECT * FROM test_audit;"
c 'Однако попытки изменить данные записаны в таблицу аудита.'

P 18
###############################################################################
h 'Встроенный пул соединений'

c 'Выделим в пуле по два процесса для каждой базы данных:'
s 1 "ALTER SYSTEM SET session_pool_size=2;"
pgctl_restart A

psql_open A 1

c 'Если начать транзакцию в основном сеансе, ей будет выделен один из процессов:'
s 1 "\c $TOPIC_DB"
s 1 "BEGIN;"
s 1 "SELECT pg_backend_pid();"
c 'Сеанс может хранить свое состояние в пользовательских параметрах:'
s 1 "SELECT set_config('my.name', 'Я — сеанс 1', false);"

c 'Транзакции, начавшейся в другом сеансе, будет выделен другой процесс:'
psql_open A 2
s 2 "\c $TOPIC_DB"
s 2 "BEGIN;"
s 2 "SELECT pg_backend_pid();"
s 2 "SELECT set_config('my.name', 'Я — сеанс 2', false);"

c "По умолчанию процессы выделяются по очереди (стратегия round-robin), поэтому третьему сеансу будет назначен процесс $PID1. Но этот процесс занят выполнением транзакции первого сеанса, поэтому третий сеанс будет ждать:"
psql_open A 3
ss 3 "\c $TOPIC_DB"

c "Когда транзакция первого сеанса заканчивается..."
s 1 "COMMIT;"

c "...третий сеанс может воспользоваться освободившимся процессом $PID1:"
r 3
s 3 "SELECT pg_backend_pid();"
s 3 "SELECT set_config('my.name', 'Я — сеанс 3', false);"

c 'Заметим, что состояние сеансов сохраняется, несмотря на то что процесс выполняет транзакции разных сеансов:'
s 1 "SELECT pg_backend_pid(), current_setting('my.name');"
s 3 "SELECT pg_backend_pid(), current_setting('my.name');"

########################################################################

stop_here
cleanup
demo_end
