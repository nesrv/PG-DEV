#!/bin/bash

. ../lib
init

start_here 4

###############################################################################

h 'Категории изменчивости и оптимизация'

c 'Благодаря дополнительной информации о поведении функции, которую дает указание категории изменчивости, оптимизатор может сэкономить на вызовах функции.'

c 'Для экспериментов создадим функцию, возвращающую случайное число:'

s 1 'CREATE FUNCTION rnd() RETURNS float
LANGUAGE sql VOLATILE 
RETURN random();'

c 'Проверим план выполнения следующего запроса:'

s 1 'EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;'

c 'В плане мы видим обращение к табличной функции generate_series в узле Function Scan. Каждая строка результата сравнивается со случайным числом и при необходимости отбрасывается фильтром, в котором вычисляется скалярная функция random.'

c 'В этом можно убедиться и воочию:'

s 1 'SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;'
s 1 '\g'
s 1 '\g'
s 1 '\g'
s 1 '\g'
c 'Здесь с разной вероятностью получаем от 0 до 10 строк.'
p

c 'Функция с категорией изменчивости Stable будет вызвана всего один раз — поскольку мы фактически указали, что ее значение не может измениться в пределах оператора:'

s 1 'ALTER FUNCTION rnd() STABLE;'
s 1 'EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;'

c 'Узел Result формирует строку выборки, а выражение One-Time Filter вычисляется один раз, так что результатом запроса будет либо 0, либо 10 строк.'
s 1 'SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;'
FIRST_RESULT=$RESULT
while [ "$RESULT" = "$FIRST_RESULT" ]; do
	s 1 '\g' # повторяем, пока не получим другой результат
done
s 1 '\g' # и ещё раз

p

c 'Наконец, категория Immutable позволяет вычислить значение функции еще на этапе планирования, поэтому во время выполнения вычисление условия фильтра уже не требуется:'

s 1 'ALTER FUNCTION rnd() IMMUTABLE;'
s 1 'EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;'
FIRST_RESULT=$RESULT
while [ "$RESULT" = "$FIRST_RESULT" ]; do
	s 1 '\g' # повторяем, пока не получим другой результат
done
s 1 '\g' # и ещё раз

c 'Для Immutable получаем случайный план!'
c 'Ответственность «за дачу заведомо ложных показаний» лежит на разработчике.'

P 6

###############################################################################
h 'Подстановка кода функций в SQL-запрос'

c 'Тело очень простых скалярных функций на языке SQL может быть подставлено прямо в основной SQL-оператор на этапе разбора запроса. В этом случае время на вызов функции не тратится.'

c 'Пример мы уже видели: наша функция rnd().'
c 'Проверим, какой будет план запроса в случае, когда категория изменчивости функции rnd (Stable) не соответствует категории изменчивости функции random (Volatile):'

s 1 'ALTER FUNCTION rnd() STABLE;'
s 1 'EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;'

c 'В фильтре упоминается функция rnd().'

c 'Поменяем категорию изменчивости функции на Volatile:'

s 1 'ALTER FUNCTION rnd() VOLATILE;'
s 1 'EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;'

c 'Теперь в фильтре упоминается функция random(), но не rnd(). Она будет вызываться напрямую, минуя «обертку» в виде функции rnd().'

p

c 'Возможностей для подстановки табличных функций гораздо больше. Например, в таких функциях допускаются обращения к таблицам.'

s 1 "CREATE FUNCTION flights_from(airport_name text)
RETURNS SETOF flights
AS \$\$
  SELECT f.*
  FROM flights f
    JOIN airports a ON f.departure_airport = a.airport_code
  WHERE a.airport_name = flights_from.airport_name;
\$\$
LANGUAGE sql STABLE;"

c 'При подстановке табличные функции работают наподобие представлений с параметрами. Планировщик оптимизирует весь запрос, функция прозрачна для него:'

s 1 "EXPLAIN (costs off)
SELECT *
FROM flights_from('Оренбург')
WHERE status = 'Arrived';"

P 8

###############################################################################
h 'Табличные функции'

c 'Вызовем функцию generate_series в предложении FROM с ограничением на количество строк (LIMIT):'

s 1 "\set timing on"
s 1 "EXPLAIN (analyze, costs off)
SELECT * FROM generate_series(1,10_000_000)
LIMIT 10;"
  
c 'В плане запроса видим узел Function Scan — сначала были получены все строки из функции, и только потом наложено ограничение LIMIT.'

c 'А теперь повторим запрос, только вызовем функцию из предложения SELECT:'

s 1 "EXPLAIN (analyze, costs off)
SELECT generate_series(1,10_000_000)
LIMIT 10;"

c 'Теперь в плане появился узел ProjectSet, который формирует десять строк выборки — в данном случае оптимизатору удалось получать строки по требованию. Время выполнения запроса сократилось на порядки.'
c 'Узел Result здесь представляет опущенное в запросе предложение FROM — он передает родительскому узлу ровно одну строку.'

s 1 "\set timing off"

p

c 'Однако не все функции могут возвращать строки по одной. Например, обращение к любой функции на языке PL/pgSQL возвращает все строки результата:'

s 1 "CREATE FUNCTION plpgsql_rows() RETURNS SETOF integer
AS \$\$
BEGIN
  RETURN QUERY
    SELECT * FROM generate_series(1,10_000_000);
END
\$\$ LANGUAGE plpgsql;"

c 'Вызовем функцию из предложения SELECT:'

s 1 "\timing on"
s 1 "EXPLAIN (analyze, costs off)
SELECT plpgsql_rows() LIMIT 10;"
s 1 "\timing off"
  
c 'В плане — узел ProjectSet, но теперь серверу приходится получить результат функции полностью, а затем наложить ограничение LIMIT. Время выполнения это хорошо показывает.'

p

c 'В предложении SELECT может быть несколько вызовов табличных функций, а сами функции могут вкладываться друг в друга:'

s 1 "SELECT generate_series(1, generate_series(1,3)), unnest(ARRAY['A','B','C']);"

s 1 "EXPLAIN (verbose, costs off)
SELECT generate_series(1, generate_series(1,3)), unnest(ARRAY['A','B','C']);"

c 'Нижний узел ProjectSet формирует выборку из результатов выполнения двух табличных функций: generate_series(1,3) и unnest. В этой выборке оказываются три строки.'
c 'Верхний узел ProjectSet формирует итоговую выборку, вычисляя внешний вызов generate_series.'

c 'Без учета материализации такой запрос эквивалентен следующему запросу, в котором функции вызываются в предложении FROM:'

s 1 "SELECT g2.i, u.c
FROM generate_series(1,3) WITH ORDINALITY AS g1(i)
  FULL JOIN LATERAL unnest(ARRAY['A','B','C']) WITH ORDINALITY AS u(c)
    ON g1.ordinality = u.ordinality
  CROSS JOIN LATERAL generate_series(1, g1.i) AS g2(i);"

P 10

###############################################################################
h 'Настройки COST и ROWS'

c 'Напишем табличную функцию на языке PL/pgSQL, выводящую дни недели:'

s 1 "CREATE FUNCTION days_of_week() RETURNS SETOF text
AS \$\$
BEGIN
    FOR i IN 7 .. 13 LOOP
        RETURN NEXT to_char(to_date(i::text,'J'),'TMDy');
    END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

s 1 "SELECT * FROM days_of_week();"

c 'План запроса:'

s 1 "EXPLAIN
SELECT * FROM days_of_week();"

c 'Стоимость выполнения функции считается постоянной, для пользовательских функций по умолчанию она равна стоимости 100 операторов:'

s 1 "SELECT 100 * current_setting('cpu_operator_cost')::float;"

c 'Но это значение можно изменить:'

s 1 "ALTER FUNCTION days_of_week COST 1000;"

s 1 "EXPLAIN
SELECT * FROM days_of_week();"

c 'В плане изменилась начальная стоимость.'

p

c 'Сервер оценивает кардинальность результата этой функции как 1000, хотя фактическое значение равно семи.'
c 'С помощью указания ROWS можно подсказать серверу ориентировочное количество строк, которое вернет функция:'

s 1 "ALTER FUNCTION days_of_week ROWS 10;"

c 'Повторим запрос:'

s 1 "EXPLAIN
SELECT * FROM days_of_week();"

c 'Теперь сервер считает, что функция вернет 10 строк, поэтому уменьшилась полная стоимость узла:'

s 1 "SELECT 1000 * current_setting('cpu_operator_cost')::float
	+ 10 * current_setting('cpu_tuple_cost')::float;"

c 'Измененные значения можно увидеть в системном каталоге:'

s 1 "SELECT procost, prorows FROM pg_proc WHERE proname='days_of_week';"

c 'Или с помощью метакоманды psql:'

s 1 "\sf days_of_week" pgsql

P 12

###############################################################################
h 'Вспомогательные функции планировщика'

c 'Посмотрим план запроса с вызовом функции generate_series:'

s 1 "EXPLAIN
SELECT n FROM generate_series(1,5) n;"

c 'В отличии от функции days_of_week, оптимизатор сразу правильно оценивает количество возвращаемых строк. Более того, оценка зависит от параметров функции:'

s 1 "EXPLAIN
SELECT n FROM generate_series(1,15) n;"

c 'Благодаря вспомогательной функции (она может быть написана только на языке С) планировщик получает дополнительную информацию, которую использует для вычисления селективности условий, кардинальности функции или ее стоимости.'

c 'Посмотреть, имеется ли вспомогательная функция, можно в таблице pg_proc:'

s 1 "SELECT left(pg_get_function_arguments(p.oid), 57) proargtypes, prosupport
FROM pg_proc p
WHERE p.proname = 'generate_series';"

c 'Как видно, вспомогательные функции существуют не для всех перегруженных вариантов функции generate_series.'
c 'Посмотрим на план запроса, генерирующего ряд дат:'

s 1 "EXPLAIN SELECT *
FROM generate_series(now(), now() + interval '5 day','1 day');"

c 'Без вспомогательной функции и указания ROWS оптимизатор не имеет информации о числе строк в результате и поэтому использует значение по умолчанию (1000).'

c 'С каждой версией в PostgreSQL появляются новые вспомогательные функции.'

P 14

###############################################################################

h 'Пометки параллельности'

c 'Пометки параллельности можно увидеть в столбце proparallel таблицы pg_proc (r=restricted, s=safe, u=unsafe):'

s 1 "SELECT proparallel, count(*)
FROM pg_proc
GROUP BY proparallel;"

c 'Все основные стандартные функции безопасны.'

p

c 'Пометки также показывает метакоманда \df+ утилиты psql (поле Parallel):'

s 1 "\x"
s 1 "\df+ random"
s 1 "\x"

p

c 'Проверим, как пометка параллельности влияет на план выполнения запроса.'

c 'Напишем функцию, вычисляющую стоимость билета. Она помечена как безопасная для параллельного выполнения:'

s 1 "CREATE FUNCTION ticket_amount(ticket_no char(13)) RETURNS numeric
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS \$\$
BEGIN
    RETURN (SELECT sum(amount)
            FROM ticket_flights tf
            WHERE tf.ticket_no = ticket_amount.ticket_no
    );
END;
\$\$;"

c 'Запрос проверяет, что общая стоимость бронирований совпадает с общей стоимостью билетов:'

s 1 "EXPLAIN (costs off)
SELECT (SELECT sum(ticket_amount(ticket_no)) FROM tickets) =
       (SELECT sum(total_amount) FROM bookings);"

c 'План запроса состоит из двух частей: в узле InitPlan 1 выполняется подзапрос с агрегацией по tickets, а подзапрос в узле InitPlan 2 выполняет агрегацию по bookings.'
c 'Сейчас оба подзапроса выполняются параллельно.'

p

c 'Поменяем пометку параллельности на UNSAFE:'

s 1 "ALTER FUNCTION ticket_amount PARALLEL UNSAFE;"

s 1 "EXPLAIN (costs off)
SELECT (SELECT sum(ticket_amount(ticket_no)) FROM tickets) =
       (SELECT sum(total_amount) FROM bookings);"

c 'Теперь оба подзапроса выполняются последовательно — пометка запрещает параллельные планы.'

p

c 'А теперь пометим функцию как ограниченно распараллеливаемую (RESTRICTED):'

s 1 "ALTER FUNCTION ticket_amount PARALLEL RESTRICTED;"

s 1 "EXPLAIN (costs off)
SELECT (SELECT sum(ticket_amount(ticket_no)) FROM tickets) =
       (SELECT sum(total_amount) FROM bookings);"

c 'Подзапрос с функцией выполняется последовательно ведущим процессом, для второго подзапроса выбран параллельный план.'

p

###############################################################################

h 'Конфигурационные параметры'

c 'В ряде случаев может оказаться удобным оформить запросы в виде хранимых подпрограмм (например, с целью предоставить к ним доступ приложению). В этом случае дополнительным преимуществом может быть возможность установки параметров для конкретных подпрограмм.'

c 'Рассмотрим в качестве примера запрос:'

s 1 "EXPLAIN (analyze, costs off, timing off)
SELECT count(*) FROM bookings;"

c 'Допустим, мы хотим использовать параллельные планы, но именно этот запрос собираемся выполнять последовательно. Тогда мы можем установить параметр на уровне функции:'

s 1 "CREATE FUNCTION count_bookings() RETURNS bigint
AS \$\$
SELECT count(*) FROM bookings;
\$\$ LANGUAGE sql STABLE;"

s 1 "ALTER FUNCTION count_bookings SET max_parallel_workers_per_gather = 0;"

c 'О том, как проверить план запроса, выполняющегося внутри функции, мы говорили в теме «Профилирование». Воспользуемся расширением auto_explain:'

s 1 "LOAD 'auto_explain';"
s 1 "SET auto_explain.log_min_duration = 0;"
s 1 "SET auto_explain.log_nested_statements = on;"

c 'Выполним запрос:'

s 1 "SELECT count_bookings();"

c 'Выведем последние строки журнала сообщений:'

e "tail -n 10 $LOG"

###############################################################################
stop_here
cleanup
demo_end
