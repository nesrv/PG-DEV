#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Индекс'

s 1 "CREATE INDEX ON tickets(passenger_name);"

###############################################################################
h '2. Наличие статистики'

c 'Некоторые основные значения:'

s 1 "SELECT reltuples, relpages FROM pg_class WHERE relname = 'tickets';"
s 1 "SELECT
    attname,
    null_frac nul,
    n_distinct,
    left(most_common_vals::text,20) mcv,
    cardinality(most_common_vals) mc,
    left(histogram_bounds::text,20) histogram,
    cardinality(histogram_bounds) hist,
    correlation
  FROM pg_stats WHERE tablename = 'tickets';"

ul 'Ни один столбец не содержит неопределенных значений.'
ul 'Уникальных номеров бронирования примерно в два раза меньше, чем строк в таблице (то есть на каждое бронирование в среднем приходится два билета). Имеется около 10000 разных имен. Все остальные столбцы содержат уникальные значения.'
ul 'Размеры массивов наиболее частых значений и гистограмм соответствуют значению параметра default_statistics_target (100).'
ul 'Для имен пассажиров есть наиболее частые значения. Для других столбцов они не имеют смысла, так как максимальное количество билетов (5) встречается в 194 бронированиях, а остальные столбцы уникальны.'
ul 'Гистограммы есть для всех столбцов, они нужны для оценки предикатов с условиями неравенства.'
ul 'Строки таблицы физически упорядочены по номеру билета. Данные в других столбцах расположены более или менее хаотично.'

###############################################################################
h '3. Планы запросов'

s 1 "EXPLAIN SELECT * FROM tickets;"

c 'Кардинальность равна числу строк в таблице; выбрано полное сканирование.'

s 1 "EXPLAIN SELECT * FROM tickets WHERE passenger_name = 'ALEKSANDR IVANOV';"

c 'Селективность оценена по списку наиболее частых значений; выбрано сканирование по битовой карте.'

s 1 "EXPLAIN SELECT * FROM tickets WHERE passenger_name = 'ANNA VASILEVA';"

c 'Селективность оценена исходя из равномерного распределения; выбрано сканирование по битовой карте.'

s 1 "EXPLAIN SELECT * FROM tickets WHERE ticket_no = '0005432000284';"

c 'Кардинальность равна 1, так как значения этого столбца уникальны; выбрано индексное сканирование.'

###############################################################################
stop_here
cleanup
demo_end
