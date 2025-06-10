#!/bin/bash

. ../lib

init
roll_to 18 # для отладчика

psql_open A 2

s 2 '\c bookstore'

# HOME for postgres - from params

e "sudo rm $H/log.txt"
s 2 'DROP EXTENSION IF EXISTS pldbgapi;'
psql_close 2

start_here 4

###############################################################################
h 'Проверки корректности'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Команда ASSERT позволяет указать условия, нарушения которых являются непредвиденной ошибкой. Можно провести определенную аналогию между такими условиями и ограничениями целостности в базе данных.'
c 'Пример: функция, возвращающее номер подъезда по номеру квартиры:'

s 1 "CREATE FUNCTION entrance(
    floors integer,
    flats_per_floor integer,
    flat_no integer
)
RETURNS integer
AS \$\$
BEGIN
    RETURN floor((flat_no - 1)::real / (floors * flats_per_floor)) + 1;
END
\$\$ LANGUAGE plpgsql IMMUTABLE;"

c 'Убедиться в правильности работы функции можно при помощи тестирования, проверив результат на некоторых «интересных» значениях:'

s 1 "SELECT entrance(9, 4, 1), entrance(9, 4, 36), entrance(9, 4, 37);"

c 'Но при некорректных входных значениях функция будет выдавать бессмысленный результат, который, например,  может быть передан дальше в другие подпрограммы, которые из-за этого тоже могут повести себя некорректно. Тестирование только кода данной функции здесь никак не поможет.'

s 1 "SELECT entrance(9, 4, 0);"

c 'Можно обезопасить себя, добавив проверку:'

s 1 "CREATE OR REPLACE FUNCTION entrance(
    floors integer,
    flats_per_floor integer,
    flat_no integer
)
RETURNS integer
AS \$\$
BEGIN
    ASSERT floors > 0 AND flats_per_floor > 0 AND flat_no > 0,
        'Некорректные входные параметры';
    RETURN floor((flat_no - 1)::real / (floors * flats_per_floor)) + 1;
END
\$\$ LANGUAGE plpgsql IMMUTABLE;"

s 1 "SELECT entrance(9, 4, 0);"

c 'Теперь некорректный вызов сразу же приведет к ошибке.'

P 6

###############################################################################
h 'Отладка с PL/pgSQL Debugger'

c 'Выполним отладку одной из функций нашего приложения.'
c 'Пакет поддержки отладчика postgresql-16-pldebugger уже установлен в виртуальной машине курса. Теперь нам нужно обеспечить загрузку разделяемой библиотеки, для этого установим параметр и перезапустим сервер:'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'plugin_debugger';"

pgctl_restart A

c 'Установим расширение отладчика в базу данных bookstore:'

psql_open A 2 bookstore
s 2 'CREATE EXTENSION pldbgapi SCHEMA public;'

c 'Для начала отладочных действий все готово. Запускаем приложение:'

open-file http://localhost true

c 'Отладку проведем с помощью графической утилиты pgAdmin 4.'

ei "/usr/pgadmin4/bin/pgadmin4 2>/dev/null"

s_bare 2 'DROP EXTENSION pldbgapi'

P 9

###############################################################################
h 'Команда RAISE'

c 'Создадим функцию для подсчета количества строк в таблице, имя которой передается во входном параметре.'

psql_open A 1 $TOPIC_DB

s 1 "CREATE FUNCTION get_count(tabname text) RETURNS bigint
AS \$\$
DECLARE
    cmd text;
    retval bigint;
BEGIN
    cmd := 'SELECT COUNT(*) FROM ' || quote_ident(tabname);
    RAISE NOTICE 'cmd: %', cmd;
    EXECUTE cmd INTO retval;
    RETURN retval; 
END
\$\$ LANGUAGE plpgsql STABLE;"

c 'Для динамического выполнения текст команды лучше предварительно записывать в переменную. В случае ошибки можно проанализировать значение этой переменной.'

s 1 "SELECT get_count('pg_class');"

c "Строка, начинающаяся с «NOTICE» — наша отладочная информация."

p

c 'RAISE можно использовать для отслеживания хода выполнения долгого запроса.'
c 'Предположим, что внутри кода, решающего некую задачу, четко выделяются три этапа выполнения. И по ходу работы подпрограммы мы хотим понимать, на каком из них находимся. Для этого на каждом этапе будем вызывать такую процедуру:'

s 1 "CREATE PROCEDURE debug_message(msg text)
AS \$\$
BEGIN
	RAISE NOTICE '%', msg;
END
\$\$ LANGUAGE plpgsql;"

c 'Основная процедура по завершении очередного этапа работы вызывает процедуру debug_message:'

s 1 "CREATE PROCEDURE long_running()
AS \$\$
BEGIN
    CALL debug_message('long_running. Stage 1/3...');
    PERFORM pg_sleep(2);
    CALL debug_message('long_running. Stage 2/3...');
    PERFORM pg_sleep(3);
    CALL debug_message('long_running. Stage 3/3...');
    PERFORM pg_sleep(1);
    CALL debug_message('long_running. Done');
END
\$\$ LANGUAGE plpgsql;"

c 'Команда RAISE выдает сообщения сразу, а не по окончании работы подпрограммы:'

s 1 'CALL long_running();'

p

c 'Такой подход удобен, когда можно вызвать функцию в отдельном сеансе. Если же функция вызывается из приложения, то удобнее писать и затем смотреть в журнал сервера.'
c 'Перепишем процедуру debug_message для выдачи сообщения с уровнем, установленным в пользовательском параметре app.raise_level:'

s 1 "CREATE OR REPLACE PROCEDURE debug_message(msg text)
AS \$\$
BEGIN
    CASE current_setting('app.raise_level', true)
        WHEN 'NOTICE'  THEN RAISE NOTICE  '%, %, %', user, clock_timestamp(), msg;
        WHEN 'DEBUG'   THEN RAISE DEBUG   '%, %, %', user, clock_timestamp(), msg;
        WHEN 'LOG'     THEN RAISE LOG     '%, %, %', user, clock_timestamp(), msg;
        WHEN 'INFO'    THEN RAISE INFO    '%, %, %', user, clock_timestamp(), msg;
        WHEN 'WARNING' THEN RAISE WARNING '%, %, %', user, clock_timestamp(), msg;
        ELSE NULL; -- все прочие значения отключают вывод сообщений
    END CASE;
END
\$\$ LANGUAGE plpgsql;"

c 'Для целей примера установим параметр на уровне сеанса:'

s 1 "SET app.raise_level TO 'NONE';"

c 'Теперь в «обычной» жизни (app.raise_level = NONE) отладочные сообщения не будут выдаваться:'

s 1 'CALL long_running();'

c "Запуская функцию в отдельном сеансе, мы можем получить отладочные сообщения, выставив app.raise_level в NOTICE:"

s 1 "SET app.raise_level TO 'NOTICE';"
s 1 "CALL long_running();"

c 'Если же мы хотим включить отладку в приложении с записью в журнал сервера, то переключаем app.raise_level в LOG:'

s 1 "SET app.raise_level TO 'LOG';"
s 1 "CALL long_running();"

c 'Смотрим в журнал сервера:'

e "tail -n 30 $LOG | grep 'long_running\.'"

c 'Управляя параметрами app.raise_level, log_min_messages и client_min_messages, можно добиться различного поведения при выводе отладочных сообщений.'
c 'Важно, что для этого не нужно менять код приложения.'

P 11

###############################################################################
h 'Статус сеанса'

c 'Посмотрим, как использовать для отладки параметр application_name. Первый сеанс меняет значение этого параметра, второй — периодически опрашивает представление pg_stat_activity.'

s 2 "\c $TOPIC_DB"

c "Новый вариант процедуры:"

s 1 "CREATE OR REPLACE PROCEDURE debug_message(msg text)
AS \$\$
BEGIN
	PERFORM set_config('application_name', format('%s', msg), /* is_local */ true);
END
\$\$ LANGUAGE plpgsql;"

c 'Запускаем в первом сеансе:'

ssi 1 'CALL long_running();'

c 'Во втором с паузой в 2 секунды обновляем строку из pg_stat_activity:'

sleep 1
si 2 "SELECT pid, usename, application_name
FROM pg_stat_activity
WHERE datname = '$TOPIC_DB' AND pid <> pg_backend_pid();"

sleep 2
si 2 '\g'
sleep 2
si 2 '\g'
sleep 2
si 2 '\g'

r 1

P 13

###############################################################################
h 'Запись в таблицу: расширение dblink'

c 'Установим расширение:'

s 1 'CREATE EXTENSION dblink;'

c 'Создаем таблицу для записи сообщений.'
c 'В таблице полезно сохранять информацию о пользователе и времени вставки. Столбец id нужен для гарантированной сортировки результата в порядке добавления строк.'

s 1 'CREATE TABLE log (
    id       integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    username text,
    ts       timestamptz,
    message  text
);'

c 'Теперь перепишем процедуру так, чтобы она добавляла записи в таблицу log. Процедура открывает новый сеанс, выполняет вставку в отдельной транзакции и закрывает сеанс.'

s 1 "CREATE OR REPLACE PROCEDURE debug_message(msg text)
AS \$\$
DECLARE
    cmd text;
BEGIN
    cmd := format(
        'INSERT INTO log (username, ts, message)
         VALUES (%L, %L::timestamptz, %L)',
        user, clock_timestamp()::text, debug_message.msg
    );
    PERFORM dblink('dbname=' || current_database(), cmd);
END
\$\$ LANGUAGE plpgsql;"

c 'Для проверки запустим процедуру long_running в отдельной транзакции, которую в конце откатим.'

s 1 "BEGIN;"
s 1 "CALL long_running();"
s 1 "ROLLBACK;"

c 'Убедимся, что в таблице сохранились все вызовы debug_message. По значениям ts можно проверить, сколько времени прошло между вызовами.'

s 1 "SELECT username, to_char(ts, 'HH24:MI:SS') as ts, message
FROM log
ORDER BY id;"

P 15

###############################################################################
h 'Запись в файл: pg_file_write'

c 'Установим расширение:'

s 1 'CREATE EXTENSION adminpack;'

c 'В очередной раз перепишем процедуру debug_message, теперь она будет записывать отладочную информацию в файл. Пользователь postgres, запустивший экземпляр СУБД, должен иметь возможность записи в этот файл, поэтому расположим его в домашнем каталоге этого пользователя.'

s 1 "CREATE OR REPLACE PROCEDURE debug_message(msg text)
AS \$\$
DECLARE
    filename CONSTANT text := '$H/log.txt';
    message text;
BEGIN
    message := format(E'%s, %s, %s\n',
        session_user, clock_timestamp()::text, debug_message.msg
    );
    PERFORM pg_file_write(filename, message, /* append */ true);
END
\$\$ LANGUAGE plpgsql;"

c 'Функция записывает отдельной строкой в файл журнала сообщение, переданное параметром, вместе с информацией о том, кто и когда записал строку.'
p

c 'Для проверки запустим long_running в отдельной транзакции, которую в конце откатим.'

s 1 "BEGIN;"
s 1 "CALL long_running();"
s 1 "ROLLBACK;"

c 'Проверим, что записи в журнале появились. Чтобы пользователь student мог получить доступ к этому файлу, нужно использовать команду sudo:'

e "sudo cat $H/log.txt"

P 19

###############################################################################
h 'Трассировка сеансов'

c "Простой пример включения трассировки — установка параметра log_statement в значение all (записывать все команды, включая DDL, модификацию данных и запросы)."

s 1 "SET log_statement = 'all';"

c 'Выполним какой-нибудь запрос:'

s 1 "SELECT get_count('pg_views');"

c "И выключим трассировку:"

s 1 "RESET log_statement;"

c "Информация о выполненных командах окажется в журнале сервера:"

e "tail -n 2 $LOG"

c 'Однако в журнал попадает только команда верхнего уровня, но не запрос внутри функции get_count.'

c 'Воспользуемся расширением auto_explain. Это расширение не нужно устанавливать в базу данных, но требуется загрузить в память. Загрузку можно настроить для всего экземпляра с помощью параметра shared_preload_libraries, либо проделать однократно для текущего процесса:'

s 1 "LOAD 'auto_explain';"

c 'Установим трассировку всех команд независимо от длительности выполнения:'

s 1 "SET auto_explain.log_min_duration = 0;"

c 'Включим трассировку вложенных запросов:'

s 1 "SET auto_explain.log_nested_statements = on;"

c 'Сообщения выводятся с помощью того же механизма, что использует команда RAISE. По умолчанию используется уровень LOG, что обычно соответствует выводу в журнал. Изменив параметр, можно получать трассировку непосредственно в консоли:'

s 1 "SET auto_explain.log_level = 'NOTICE';"

c 'Повторим запрос:'

s 1 "SELECT get_count('pg_views');"

c 'Мы видим не только вызов функции, но и вложенный запрос вместе с планами выполнения.'

###############################################################################

stop_here

e "sudo rm $H/log.txt"
s 2 '\c bookstore'
s 2 'DROP EXTENSION pldbgapi;'

cleanup
demo_end
