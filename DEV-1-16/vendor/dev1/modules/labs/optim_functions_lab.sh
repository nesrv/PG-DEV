#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Материализация изменчивых функций в CTE'

c 'Общее табличное выражение с изменчивой функцией всегда материализуется:'

s 1 'EXPLAIN (costs off)
WITH c AS (
  SELECT random()
)
SELECT * FROM c;'

c 'В этом случае указание NOT MATERIALIZED не действует:'

s 1 'EXPLAIN (costs off)
WITH c AS NOT MATERIALIZED (
  SELECT random()
)
SELECT * FROM c;'

###############################################################################
h '2. Функция-обертка'

s 1 "CREATE FUNCTION sql_rows_lab() RETURNS SETOF integer
AS \$\$
  SELECT * FROM generate_series(1,10_000_000);
\$\$ LANGUAGE sql;"

c 'По умолчанию функция имеет категорию изменчивости Volatile.'

c 'Базовый запрос:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT * FROM generate_series(1,10_000_000);"

c 'Поскольку функция вызывается в предложении FROM, происходит материализация. Памяти work_mem не хватает, все строки сбрасываются на диск (temp written) и затем считываются (temp read).'

p

c 'Вызов функции в предложении SELECT:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT sql_rows_lab();"

c 'В узле ProjectSet нет материализации, поэтому цифры temp written/read остались без изменений. Однако время выполнения сильно увеличилось: оно тратится на передачу десяти миллионов строк от узла к узлу по одной строке.'

p

c 'Вызов функции в предложении FROM:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT * FROM sql_rows_lab();"

c 'Здесь к узлу Function Scan внутри функции добавляется еще один в основном запросе, поэтому количество использованных временных страниц удваивается.'

p

c 'Сменим категорию изменчивости функции:'

s 1 "ALTER FUNCTION sql_rows_lab STABLE;"

c 'При вызове функции из предложения SELECT ничего не меняется:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT sql_rows_lab();"

p

c 'Вызовем функцию из предложения FROM:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT * FROM sql_rows_lab();"

c 'Теперь тело функции подставляется в основной запрос.'

###############################################################################
h '3. Дни недели'

c 'Функция была создана следующей командой:'

s 1 "CREATE FUNCTION days_of_week() RETURNS SETOF text
AS \$\$
BEGIN
    FOR i IN 7 .. 13 LOOP
        RETURN NEXT to_char(to_date(i::text,'J'),'TMDy');
    END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Категория изменчивости не указана, поэтому подразумевается Volatile.'
c 'Может показаться, что это постоянная функция (Immutable), поскольку у нее нет параметров и список дней недели не меняется.'

s 1 "SELECT * FROM days_of_week();"

c 'Однако названия дней недели зависят от настройки локализации. Текущее значение:'

s 1 "\dconfig lc_time"

c 'Изменим настройку:'

s 1 "SET lc_time = 'en_US.UTF8';"

s 1 "SELECT * FROM days_of_week();"

c 'Теперь функция возвращает названия дней недели на английском языке, поэтому правильным будет задать категорию Stable:'

s 1 "ALTER FUNCTION days_of_week() STABLE;"

stop_here
cleanup
demo_end
