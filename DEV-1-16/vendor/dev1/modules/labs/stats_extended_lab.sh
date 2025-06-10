#!/bin/bash

. ../lib
init
start_here

###############################################################################

h '1. Затраты на анализ'

c 'Создадим расширенные статистики аналогично тому, как это было сделано в демонстрации.'

c 'Статистика по функциональной зависимости:'

s 1 "CREATE STATISTICS flights_dep(dependencies)
ON flight_no, departure_airport FROM flights;"

c 'Списки наиболее частых комбинаций значений:'

s 1 "CREATE STATISTICS flights_mcv(mcv) 
ON departure_airport, aircraft_code FROM flights;"

c 'Статистика по уникальным комбинациям значений:'

s 1 "CREATE STATISTICS flights_nd(ndistinct)
ON departure_airport, arrival_airport FROM flights;"

c 'Измерим время анализа.'

s 1 "\timing on"

s 1 "ANALYZE flights;"

c 'В первый раз анализ может занимать существенно больше времени, чем обычно.'

s 1 "ANALYZE flights;"
s 1 "ANALYZE flights;"

s 1 "\timing off"

c 'Удалим созданные расширенные статистики:'

s 1 "DROP STATISTICS flights_dep;"
s 1 "DROP STATISTICS flights_mcv;"
s 1 "DROP STATISTICS flights_nd;"

c 'Повторно измеряем время:'

s 1 "\timing on"

s 1 "ANALYZE flights;"
s 1 "ANALYZE flights;"

s 1 "\timing off"

c 'Было создано всего три расширенные статистики, но время анализа до и после удаления заметно различается. С увеличением количества собираемых расширенных статистик будет расти и время на анализ, что может привести к увеличению нагрузки на сервер.'

c 'Поэтому использовать расширенную статистику нужно осмысленно и только в тех случаях, когда это необходимо.'

###############################################################################

h '2. Применение расширенной статистики'

c 'Перелеты в бизнес-классе стоимостью свыше 100 тысяч ₽:'

where="WHERE fare_conditions = 'Business' and amount > 100_000"

s 1 "EXPLAIN (analyze, timing off, summary off)
SELECT *
FROM ticket_flights
$where;"

c 'Оптимизатор ошибается на порядок. Причина в том, что стоимость билета и класс обслуживания коррелируют между собой, поэтому расширенная статистика должна помочь исправить оценку. Поскольку между столбцами нет прямой функциональной зависимости, добавим статистику по наиболее частым значениям:'

s 1 "CREATE STATISTICS (mcv) ON fare_conditions, amount FROM ticket_flights;"

s 1 "ANALYZE ticket_flights;"

s 1 "EXPLAIN (timing off, summary off)
SELECT *
FROM ticket_flights
$where;"

c 'Оценка немного улучшилась, но все еще сильно отличается от точного значения. Можно заметить, что доля строк, удовлетворяющих условию, немногим более 1%:'

s 1 "SELECT count(*) FILTER ($where)
  / count(*)::float
FROM ticket_flights;"

c 'Поскольку по умолчанию хранится 100 наиболее частых пар, среди них с большой вероятностью встретится не более 1–2 удовлетворяющих условию, и из-за этого оценка оптимизатора не будет адекватной. Попробуем повысить точность, увеличив объем статистики:'

s 1 "ALTER STATISTICS ticket_flights_fare_conditions_amount_stat SET STATISTICS 500;"

s 1 "ANALYZE ticket_flights;"

s 1 "EXPLAIN (timing off, summary off)
SELECT *
FROM ticket_flights
$where;"

c 'Оценка стала практически точной.'

###############################################################################
stop_here
cleanup
demo_end
