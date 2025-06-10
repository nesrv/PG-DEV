#!/bin/bash

. ../lib

init

psql_open A 2

start_here

###############################################################################
h '1. Уровень изоляции в PL/pgSQL-коде'

s 1 "DO \$\$
BEGIN
    COMMIT;
    RAISE NOTICE '%', current_setting('transaction_isolation');
END;
\$\$;"

c 'Уровень изоляции новой транзакции назначается в соответствии с параметром default_transaction_isolation:'
s 1 "SHOW default_transaction_isolation;"

c 'Сменить уровень можно командой SET TRANSACTION:'
s 1 "DO \$\$
BEGIN
    COMMIT;
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    RAISE NOTICE '%', current_setting('transaction_isolation');
END;
\$\$;"

c 'В процедуре такой код тоже сработает, но задать уровень первоначальной транзакции не получится:'
s 1 "CREATE OR REPLACE PROCEDURE test() LANGUAGE plpgsql AS \$\$
BEGIN
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    RAISE NOTICE '%', current_setting('transaction_isolation');
END;
\$\$;"
s 1 "CALL test();"

c 'Можно в начале блока добавить COMMIT и тем самым начать новую транзакцию:'
s_fake 1 "
...
BEGIN
    COMMIT;
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
..."

c 'Но более правильный вариант — задать параметр default_transaction_isolation:'
s 1 "CREATE OR REPLACE PROCEDURE test() LANGUAGE plpgsql AS \$\$
BEGIN
    RAISE NOTICE '%', current_setting('transaction_isolation');
END;
\$\$;"
s 1 "SET default_transaction_isolation = 'serializable';"
s 1 "CALL test();"

stop_here
cleanup
