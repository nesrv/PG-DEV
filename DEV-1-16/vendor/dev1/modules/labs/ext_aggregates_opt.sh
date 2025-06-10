#!/bin/bash

. ../lib

init

start_here ...

###############################################################################
h '1. Средневзвешенное значение'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Рассмотрим задачу на примере данных об оценках за экзаменационные работы. Пусть в экзаменационный билет входят теоретические вопросы (тип 1) и практические задания (тип 2), причем задания имеют больший вес в итоговой оценке.'

s 1 "CREATE TABLE results (
    student text,
    task_type integer CHECK (task_type IN (1,2)),
    task_score float CHECK (task_score BETWEEN 1 AND 10)
);"

s 1 "INSERT INTO results(student, task_type, task_score) VALUES
    ('Иванов', 1, 4),
    ('Иванов', 1, 6),
    ('Иванов', 2, 10),
    ('Петров', 1, 8),
    ('Петров', 1, 10),
    ('Петров', 2, 5);"

c 'Состояние опишем как составной тип, состоящий из суммы произведений значений на соответствующий вес и суммы весов:'

s 1 "CREATE TYPE w_avg_state AS (
  w_accum float,
  w_sum float
);"


c 'Функция перехода будет получать (кроме состояния) три параметра: текущее значение, его тип и массив весов:'

s 1 "CREATE FUNCTION w_avg_transition(
    state w_avg_state,
    val float,
    val_type bigint,
    weight float[]
)
RETURNS w_avg_state AS \$\$
DECLARE
    w float := coalesce(weight[val_type], 0);
BEGIN
    RAISE NOTICE '%(%) + % * % [%]', state.w_accum, state.w_sum, val, w, val_type;
    RETURN ROW (state.w_accum + coalesce(val, 0) * w, state.w_sum + w)::w_avg_state;
END;
\$\$ LANGUAGE plpgsql IMMUTABLE;"


c 'Функция финализации вычисляет средневзвешенное как отношение суммы произведений значений на соответствующие веса к сумме весов:'

s 1 "CREATE FUNCTION w_avg_final(
    state w_avg_state
)
RETURNS float AS \$\$
BEGIN
    RAISE NOTICE '= %(%)', state.w_accum, state.w_sum;
    RETURN CASE
        WHEN state.w_sum > 0 THEN state.w_accum / state.w_sum
    END;
END;
\$\$ LANGUAGE plpgsql IMMUTABLE;"


c 'Теперь объявляем агрегат:'

s 1 "CREATE AGGREGATE w_avg(float, bigint, float[]) (
    stype     = w_avg_state,
    initcond  = '(0, 0)',
    sfunc     = w_avg_transition,
    finalfunc = w_avg_final
);"


c 'А теперь подсчитаем средневзвешенные оценки за экзамен, сданный студентами, полагая, что решение практической задачи вдвое ценнее ответа на теоретический вопрос:'

s 1 "SELECT student, w_avg(task_score, task_type, ARRAY[1, 2])
FROM results
GROUP BY student;"

###############################################################################
h '2. Округление копеек'

s 1 "CREATE TABLE rent (
    renter text PRIMARY KEY,
    area integer
);"

s 1 "INSERT INTO rent VALUES ('A',100), ('B',100), ('C',100);"

c 'Состояние агрегатной функции будет включать округленную сумму и ошибку округления:'

s 1 "CREATE TYPE round2_state AS (
    rounded_amount numeric,
    rounding_error numeric
);"

c 'Функция перехода добавляет к состоянию округленную сумму и ошибку округления. А если ошибка округления переваливает за полкопейки, то добавляет копейку к сумме.'

s 1 "CREATE FUNCTION round2_transition(
    state round2_state,
    val numeric
)
RETURNS round2_state AS \$\$
BEGIN
    state.rounding_error :=
        state.rounding_error + val - round(val,2);
    state.rounded_amount :=
        round(val,2) + round(state.rounding_error, 2);
    state.rounding_error :=
        state.rounding_error - round(state.rounding_error, 2);
    RETURN state;
END;
\$\$ LANGUAGE plpgsql IMMUTABLE;"

c 'Функция финализации возвращает округленную сумму:'

s 1 "CREATE FUNCTION round2_final(
    state round2_state
)
RETURNS numeric
LANGUAGE sql IMMUTABLE
RETURN state.rounded_amount;"

c 'Объявляем агрегат:'

s 1 "CREATE AGGREGATE round2(numeric) (
    stype     = round2_state,
    initcond  = '(0,0)',
    sfunc     = round2_transition,
    finalfunc = round2_final
);"

c 'Пробуем. Нам нужен какой-то определенный, но не важно какой именно, порядок просмотра строк. В данном случае подходит арендатор, поскольку он уникален.'

s 1 "WITH t AS (
    SELECT *, sum(area) OVER () total_area
    FROM rent
)
SELECT *, round2( 1000.00 * area / total_area ) OVER (ORDER BY renter)
FROM t;"

###############################################################################

stop_here
cleanup
