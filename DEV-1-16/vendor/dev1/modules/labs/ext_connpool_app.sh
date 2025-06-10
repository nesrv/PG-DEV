#!/bin/bash

. ../lib

init 7

start_here

###############################################################################
h '1. Корректная работа с пулом соединений'

c 'Проблема состоит в том, что функция, проверяющая токен, запоминает пользователя в параметре сервера на уровне сеанса:'

s 1 "\sf check_auth" pgsql

c 'Это работает, когда для каждого клиента (в нашем случае — страницы приложения) используется собственный сеанс. Но в случае пула соединений все клиенты могут обслуживаться одним сеансом.'

c 'Исправление состоит в том, чтобы честно выполнять проверку каждый раз при вызове функции:'

s 1 "CREATE OR REPLACE FUNCTION check_auth(auth_token uuid) RETURNS bigint
AS \$\$
DECLARE
    user_id bigint;
BEGIN
    SELECT s.user_id
    INTO STRICT user_id
    FROM sessions s
    WHERE s.auth_token = check_auth.auth_token;
    RETURN user_id;
END;
\$\$ LANGUAGE plpgsql STABLE;"

###############################################################################
h '2. Трассировка'

c 'Функция трассировки для админки:'

s 1 "CREATE OR REPLACE FUNCTION empapi.trace() RETURNS void
LANGUAGE sql SECURITY DEFINER
RETURN set_config(
               'log_min_duration_statement',
               '0',
               /* is_local */ true
       );"

c 'Обратите внимание, что параметр устанавливается на время транзакции (третий параметр).'

c 'Функция трассировки для магазина:'

s 1 "CREATE OR REPLACE FUNCTION webapi.trace(auth_token uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER
RETURN ROW(set_config(
	    'log_min_duration_statement', '0', /* is_local */ true
	    ),
	   set_config(
	    'application_name',
	    (SELECT 'client=' || u.username
	    FROM users u JOIN sessions s ON u.user_id = s.user_id
	    WHERE s.auth_token = trace.auth_token), /* is_local */ true
	    )
	);"

c 'Чтобы имя пользователя попало в журнал сообщений, необходимо изменить параметр log_line_prefix, например, так:'

s 1 "ALTER SYSTEM SET log_line_prefix = '%m [%p] %q%u@%d (%a) ';"
s 1 "SELECT pg_reload_conf();"

c 'Здесь к стандартному выводу добавлено имя приложения.'

c 'Проверим.'

s 1 "SELECT webapi.login('alice');"
TOKEN=`echo $RESULT | head -n 3 | tail -n 1 | xargs`

s 1 "BEGIN;"
s 1 "SELECT webapi.trace('$TOKEN');"
s 1 "SELECT 2+2;"
s 1 "COMMIT;"

e "tail -n 1 $LOG_A"

c 'Теперь этим функционалом можно пользоваться, устанавливая в приложении признак трассировки в служебной панели.'

###############################################################################

stop_here
cleanup_app
