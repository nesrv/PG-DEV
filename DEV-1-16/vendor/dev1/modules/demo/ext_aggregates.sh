#!/bin/bash

. ../lib

init

start_here 4

###############################################################################
h 'Агрегатные функции'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Мы будем писать функцию для получения среднего, аналог встроенной функции avg.'
c 'Начнем с того, что создадим таблицу:'

s 1 "CREATE TABLE test (
    n float,
    grp text
);"

s 1 "INSERT INTO test(n,grp)
VALUES (1,'A'), (2,'A'), (3,'B'), (4,'B'), (5,'B');"

c 'Состояние должно включать сумму значений и их количество. Для его хранения создадим составной тип:'

s 1 "CREATE TYPE average_state AS (
    accum float,
    qty float
);"

c 'Теперь определим функцию перехода. Она возвращает новое состояние на основе текущего, прибавляя текущее значение к сумме и единицу к количеству.'
c 'Мы также включим в функцию отладочный вывод, чтобы иметь возможность наблюдать за ее вызовом.'

s 1 "CREATE FUNCTION average_transition(
    state average_state,
    val float
)
RETURNS average_state AS \$\$
BEGIN
    RAISE NOTICE '%(%) + %', state.accum, state.qty, val;
    RETURN ROW(state.accum+val, state.qty+1)::average_state;
END;
\$\$ LANGUAGE plpgsql IMMUTABLE;"

c 'Функция финализации делит полученную сумму на количество, чтобы получить среднее:'

s 1 "CREATE FUNCTION average_final(
    state average_state
)
RETURNS float AS \$\$
BEGIN
    RAISE NOTICE '= %(%)', state.accum, state.qty;
    RETURN CASE
        WHEN state.qty > 0 THEN state.accum/state.qty
    END;
END;
\$\$ LANGUAGE plpgsql IMMUTABLE;"

c 'И наконец нужно создать агрегат, указав тип состояния и его начальное значение, а также функции перехода и финализации:'

s 1 "CREATE AGGREGATE average(float) (
    stype     = average_state,
    initcond  = '(0,0)',
    sfunc     = average_transition,
    finalfunc = average_final
);"

c 'Можно пробовать нашу агрегатную функцию в работе:'

s 1 "SELECT average(n) FROM test;"

c 'Благодаря отладочному выводу хорошо видно, как изменяется начальное состояние (0,0).'

c 'Функция работает и при указании группировки GROUP BY:'

s 1 "SELECT grp, average(n) FROM test GROUP BY grp;"

c 'Здесь видно, что используются два разных состояния — свое для каждой группы.'

P 6

###############################################################################
h 'OVER()'

c 'Созданная нами агрегатная функция работает как оконная без всяких изменений:'

s 1 "SELECT n, average(n) OVER() FROM test;"

c 'Обратите внимание, что, поскольку рамка для всех строк одинакова, значение вычисляется только один раз, а не для для каждой строки.'

c 'И для предложения PARTITION BY:'

s 1 "SELECT n, grp, average(n) OVER(PARTITION BY grp) FROM test;"

c 'Здесь все работает точно так же, как для обычной группировки GROUP BY.'

P 8

###############################################################################
h 'OVER(ORDER BY)'

c 'Если добавить к определению окна предложение ORDER BY, получим рамку, «хвост» которой стоит на месте, а голова движется вместе с текущей строкой:'

s 1 "SELECT n, average(n) OVER(ORDER BY n) FROM test;"

c 'Снова не понадобилось никаких изменений — все работает. Здесь видно, как каждая следующая строка последовательно добавляется к состоянию и вызывается функция финализации.'

p

c 'Полная форма того же запроса выглядит так:'

s_fake 1 "SELECT n, average(n) OVER(
    ORDER BY n                       -- сортировка
    ROWS BETWEEN UNBOUNDED PRECEDING -- от самого начала
             AND CURRENT ROW         -- до текущей строки
)
FROM test;"

c 'То же самое работает и в сочетании с PARTITION BY:'

s 1 "SELECT n, grp, average(n) OVER(PARTITION BY grp ORDER BY n)
FROM test;"

P 10

###############################################################################
h 'OVER(ROWS BETWEEN)'

c 'С помощью фразы ROWS BETWEEN можно задать любую необходимую конфигурацию рамки, указывая (в частности):'
ul 'UNBOUNDED PRECEDING — с самого начала;'
ul 'n PRECEDING — n предыдущих;'
ul 'CURRENT ROW — текущая строка;'
ul 'n FOLLOWING — n следующих;'
ul 'UNBOUNDED FOLLOWING — до самого конца.'

c 'Рассмотрим вычисление «скользящего среднего» для трех значений. В отличие от предыдущих примеров из состояния должно «вычитаться» значение, уходящее из рамки, но у нас есть только функция «добавления». Единственный способ выполнить запрос — пересчитывать всю рамку заново:'

s 1 "SELECT n, average(n) OVER(ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
FROM test;"

p

c 'Это, конечно, неэффективно, но мы можем написать недостающую функцию «инверсии»:'

s 1 "CREATE FUNCTION average_inverse(
    state average_state,
    val float
) RETURNS average_state AS \$\$
BEGIN
    RAISE NOTICE '%(%) - %', state.accum, state.qty, val;
    RETURN ROW(state.accum-val, state.qty-1)::average_state;
END;
\$\$ LANGUAGE plpgsql IMMUTABLE;"

c 'Нужно указать эту функцию в определении агрегата:'

s 1 "DROP AGGREGATE average(float);"
s 1 "CREATE AGGREGATE average(float) (
    -- обычный агрегат
    stype      = average_state,
    initcond   = '(0,0)',
    sfunc      = average_transition,
    finalfunc  = average_final,
    -- вариант с обратной функцией
    mstype     = average_state,
    minitcond  = '(0,0)',
    msfunc     = average_transition,
    minvfunc   = average_inverse,
    mfinalfunc = average_final
);"

c 'Пробуем:'

s 1 "SELECT n, average(n) OVER(ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
FROM test;"

c 'Теперь лишние операции не выполняются.'

P 12

###############################################################################
h 'Параллелизм'

c 'Таблица с пятью строчками, конечно, слишком мала для параллельного выполнения. Возьмем больше данных:'

s 1 "CREATE TABLE big (
    n float
);"
s 1 "INSERT INTO big
    SELECT random()*10::integer FROM generate_series(1,1_000_000);"
s 1 "ANALYZE big;"

c 'Встроенные агрегатные функции могут выполняться в параллельном режиме:'

s 1 "EXPLAIN SELECT sum(n) FROM big;"

c 'А наша функция — нет:'

s 1 "EXPLAIN SELECT average(n) FROM big;"

p

c 'Чтобы поддержать параллельное выполнение, требуется еще одна функция для объединения двух состояний:'

s 1 "CREATE FUNCTION average_combine(
    state1 average_state,
    state2 average_state
) RETURNS average_state AS \$\$
BEGIN
    RAISE NOTICE '%(%) & %(%)',
        state1.accum, state1.qty, state2.accum, state2.qty;
    RETURN ROW(
        state1.accum+state2.accum, 
        state1.qty+state2.qty
    )::average_state;
END;
\$\$ LANGUAGE plpgsql IMMUTABLE;"

c 'Кроме того, уберем отладочный вывод из функции перехода:'

s 1 "CREATE OR REPLACE FUNCTION average_transition(
    state average_state,
    val float
)
RETURNS average_state
LANGUAGE sql IMMUTABLE
RETURN ROW(state.accum+val, state.qty+1)::average_state;"

c 'Пересоздадим агрегат, указав новую функцию и подтвердив безопасность параллельного выполнения:'

s 1 "DROP AGGREGATE average(float);"
s 1 "CREATE AGGREGATE average(float) (
    -- обычный агрегат
    stype       = average_state,
    initcond    = '(0,0)',
    sfunc       = average_transition,
    finalfunc   = average_final,
    combinefunc = average_combine,
    parallel    = safe,
    -- вариант с обратной функцией
    mstype      = average_state,
    minitcond   = '(0,0)',
    msfunc      = average_transition,
    minvfunc    = average_inverse,
    mfinalfunc  = average_final
);"

c 'Теперь наша функция тоже работает параллельно:'

s 1 "EXPLAIN SELECT average(n) FROM big;"
s 1 "SELECT average(n) FROM big;"

c 'Здесь видно, что три процесса поделили работу примерно поровну, и затем три состояния были попарно объединены.'

c 'В оконном режиме параллельное выполнение не поддерживается, в том числе и для встроенных функций.'

###############################################################################

stop_here
cleanup
demo_end
