#!/bin/bash

. ../lib
init
start_here

###############################################################################
h '1. Долгий запрос'

s 1 '\timing on'

c 'Обычный оператор:'

s 1 "DO \$\$
BEGIN
  FOR i IN 1..10 LOOP
    EXECUTE 'SELECT avg(amount) FROM ticket_flights';
  END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Подготовленный оператор:'

s 1 "DO \$\$
BEGIN
  FOR i IN 1..10 LOOP
    PERFORM avg(amount) FROM ticket_flights;
  END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Время изменилось незначительно — большую часть занимает выполнение запроса.'

###############################################################################
h '2. Быстрый запрос'

c 'Обычный оператор:'

s 1 "DO \$\$
BEGIN
  FOR i IN 1..100_000 LOOP
    EXECUTE 'SELECT * FROM bookings WHERE book_ref = ''0824C5''';
  END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Подготовленный оператор:'

s 1 "DO \$\$
BEGIN
  FOR i IN 1..100_000 LOOP
    PERFORM * FROM bookings WHERE book_ref = '0824C5';
  END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Время сократилось существенно — разбор и планирование занимают большую часть общего времени.'

###############################################################################
stop_here
cleanup
demo_end
