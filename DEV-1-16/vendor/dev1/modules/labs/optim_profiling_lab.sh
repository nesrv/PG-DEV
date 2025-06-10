#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Отчет'

s 1 "CREATE FUNCTION qty(aircraft_code char, fare_conditions varchar)
RETURNS bigint AS \$\$
  SELECT count(*)
  FROM flights f 
    JOIN boarding_passes bp ON bp.flight_id = f.flight_id 
    JOIN seats s ON s.aircraft_code = f.aircraft_code AND s.seat_no = bp.seat_no 
  WHERE f.aircraft_code = qty.aircraft_code AND s.fare_conditions = qty.fare_conditions;
\$\$ STABLE LANGUAGE sql;"

s 1 "CREATE FUNCTION report()
RETURNS TABLE(model text, economy bigint, comfort bigint, business bigint)
AS \$\$
DECLARE
  r record;
BEGIN 
  FOR r IN SELECT a.aircraft_code, a.model FROM aircrafts a ORDER BY a.model LOOP
    report.model := r.model;
    report.economy := qty(r.aircraft_code, 'Economy');
    report.comfort := qty(r.aircraft_code, 'Comfort');
    report.business := qty(r.aircraft_code, 'Business');
    RETURN NEXT;
  END LOOP;
END;
\$\$ STABLE LANGUAGE plpgsql;"

c 'Включаем вывод операторов и времени их выполнения в журнал:'

s 1 "SET log_min_duration_statement = 0;"

s 1 "SELECT * FROM report();"

###############################################################################
h '2. Сообщения в журнале'

e "tail -n 1 $LOG"

c 'Вложенные SQL-операторы не выводятся.'

###############################################################################
h '3. Расширение auto_explain'

s 1 "LOAD 'auto_explain';"

s 1 "RESET log_min_duration_statement;"
s 1 "SET compute_query_id = on; -- для вывода идентификаторов запросов"
s 1 "SET auto_explain.log_min_duration = 0;"
s 1 "SET auto_explain.log_nested_statements = on;"
s 1 "SET auto_explain.log_verbose = on;"

s 1 "SELECT * FROM report();"

c 'Выведем несколько последних строк журнала сообщений:'

e "tail -n 50 $LOG"

c 'В журнал попадают вложенные запросы и планы выполнения — собственно, это и есть основная функция расширения.'
c 'Помимо этого, с указанными настройками в журнал попадают параметры запроса (строка Query Parameters) и идентификатор запроса (строка Query Identifier).'

###############################################################################
stop_here
cleanup
demo_end
