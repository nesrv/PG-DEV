#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Выполнение запроса с сортировкой'

c 'Выполним запрос со значениями параметров по умолчанию:'

s 1 'EXPLAIN (analyze, buffers, costs off, timing off)
SELECT *
FROM flights
ORDER BY scheduled_departure;'

c 'Сервер выбрал внешнюю сортировку (Sort Method: external merge).'

c 'Обратите внимание на количество страниц и тип ввода-вывода (Buffers): значения temp read и written говорят о том, что сервер использовал временные файлы.'
c 'Выполните запрос повторно несколько раз — видно, что серверу всегда не хватает оперативной памяти.'

c 'Увеличим значение параметра work_mem до 32 Мбайт:'

s 1 "SET work_mem = '32 MB';"

c 'Увеличив work_mem, мы позволяем серверу использовать больше оперативной памяти для сортировки.'

c 'Повторно выполним запрос и сравним планы выполнения:'

s 1 "EXPLAIN (analyze, buffers, costs off, timing off)
SELECT *
FROM flights
ORDER BY scheduled_departure;"

c 'Теперь сервер использует сортировку в памяти (Sort Method: quicksort), в строке Buffers исчезли поля temp read и written.'

###############################################################################
h '2. Построение индекса'

c 'Включим журналирование временных файлов:'

s 1 'SET log_temp_files = 0;'

c 'Текущее значение maintenance_work_mem:'

s 1 'SHOW maintenance_work_mem;'

c 'Создаем индекс:'

s 1 '\timing on'
s 1 "CREATE INDEX ON tickets(passenger_name, passenger_id);"

c 'Временный файл понадобился:'

e "tail -n 2 $LOG"

stop_here
cleanup
demo_end
