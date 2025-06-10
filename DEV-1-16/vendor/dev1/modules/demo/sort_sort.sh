#!/bin/bash

. ../lib
init

start_here 4

###############################################################################
h 'Получение отсортированных данных'

c 'Индексный доступ автоматически возвращает строки, отсортированные по проиндексированному столбцу:'

s 1 "EXPLAIN (costs off)
SELECT * FROM flights 
ORDER BY flight_id;"

c 'Но если попросить сервер отсортировать данные по столбцу без индекса, потребуется два отдельных шага: получение данных и сортировка.'

s 1 "EXPLAIN (costs off)
SELECT * FROM flights 
ORDER BY status;"

c 'Дальше мы будем разбираться, как устроена сортировка в узле Sort.'

P 6

###############################################################################
h 'Сортировка в памяти'

c 'В распоряжении планировщика имеется несколько методов сортировки. В следующем примере используется быстрая сортировка (Sort Method: quicksort). В той же строке указан объем использованной памяти:'

s 1 "EXPLAIN (analyze, timing off, summary off)
SELECT *
FROM seats
ORDER BY seat_no;"

c 'Чтобы начать выдавать данные, узлу Sort нужно полностью отсортировать набор строк. Поэтому начальная стоимость узла включает в себя полную стоимость чтения таблицы. В общем случае сложность быстрой сортировки равна O(M logM), где M — число строк в исходном наборе.'

p

c 'Если набор строк ограничен, планировщик может переключиться на частичную сортировку (грубо говоря, вместо полной сортировки здесь 100 раз находится минимальное значение):'

s 1 "EXPLAIN (analyze, timing off, summary off)
SELECT *
FROM seats
ORDER BY seat_no
LIMIT 100;"

c 'Обратите внимание, что стоимость запроса снизилась и для сортировки потребовалось меньше памяти. В общем случае сложность алгоритма top-N heapsort ниже, чем для быстрой сортировки — она равна O(M logN).'

P 10

###############################################################################
h 'Внешняя сортировка'

c 'Пример плана с внешней сортировкой (Sort Method: external merge):'

s 1 "EXPLAIN (analyze, buffers, timing off, summary off)
SELECT *
FROM flights
ORDER BY scheduled_departure;"

c 'Обратите внимание на то, что узел Sort записывает и читает временные данные (temp read и written).'

p

c 'Увеличим значение work_mem:'

s 1 "SET work_mem = '48MB';"

s 1 "EXPLAIN (analyze, buffers, timing off, summary off)
SELECT *                          
FROM flights
ORDER BY scheduled_departure;"

c 'Теперь все строки поместились в память, и планировщик выбрал более дешевую быструю сортировку.'

s 1 "RESET work_mem;"

P 12

###############################################################################
h 'Инкрементальная сортировка'

c 'Инкрементальная сортировка может использовать как сортировку в памяти, так и внешнюю сортировку.'
c 'Для иллюстрации создадим индекс на таблице bookings:'

s 1 "CREATE INDEX ON bookings(total_amount);"

c 'Посмотрим на пример инкрементальной сортировки:'

s 1 "EXPLAIN (analyze, costs off, timing off, summary off) 
SELECT *
FROM bookings
ORDER BY total_amount, book_date;"

c 'Здесь данные, полученные из таблицы bookings по только что созданному индексу bookings_total_amount_idx, уже отсортированы по столбцу total_amount (Presorted Key), поэтому остается доупорядочить строки по столбцу book_date.'
c 'Строка Pre-sorted Groups относится к крупным группам, которые досортировывались по столбцу book_date, а строка Full-sort Groups — к небольшим группам, которые были объединены и отсортированы полностью. В примере все группы поместились в выделенную память и применялась быстрая сортировка.'

c 'Уменьшим work_mem и повторим запрос:'

s 1 "SET work_mem = '128 kB';"

s 1 "EXPLAIN (analyze, costs off, timing off, summary off) 
SELECT *
FROM bookings
ORDER BY total_amount, book_date;"

c 'Теперь, при нехватке памяти, для некоторых крупных групп пришлось применить внешнюю сортировку с использованием временных файлов  (Pre-sorted Groups ... external merge).'

s 1 "RESET work_mem;"

P 14

###############################################################################
h 'В параллельных планах'

c 'Запрос, сортирующий большую таблицу по неиндексированному полю, может выполняться параллельно:'

s 1 "EXPLAIN (analyze, costs off, timing off, summary off)
SELECT *
FROM bookings
ORDER BY book_date;"

c 'Здесь каждый процесс читает и сортирует свою часть таблицы, а затем отсортированные наборы сливаются при передаче их ведущему процессу с сохранением порядка.'

P 17

###############################################################################
h 'Оконные функции'

c 'Посмотрим план запроса, вычисляющего сумму бронирований нарастающим итогом:'

s 1 "EXPLAIN SELECT *, sum(total_amount) OVER (ORDER BY book_date)
FROM bookings;"

c 'Оконная функция вычисляется в узле WindowAgg, который получает отсортированные данные от дочернего узла Sort.'

p

c 'Добавление к запросу других оконных функций, использующих тот же порядок строк (не обязательно с совпадающим окном), а также предложения ORDER BY не приводит к появлению лишних сортировок:'

s 1 "EXPLAIN SELECT *,
  sum(total_amount) OVER (ORDER BY book_date),
  avg(total_amount) OVER (ORDER BY book_date ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING)
FROM bookings
ORDER BY book_date;"

c 'Здесь два узла WindowAgg (каждый для своего окна), но общий узел Sort. Стоимость запроса увеличилась, но лишь немного.'

p

c 'Конечно, оконные функции, требующие разного порядка строк, вынуждают сервер пересортировывать данные:'

s 1 "EXPLAIN SELECT *,
  sum(total_amount) OVER (ORDER BY book_date),
  count(*) OVER (ORDER BY book_ref)
FROM bookings;"

c 'В этом примере нижний узел WindowAgg (соответствующий функции count) получает упорядоченный набор строк по индексу, а для верхнего узла WindowAgg (соответствующего функции sum) строки переупорядочивает узел Sort.'

p

c 'Сортировка в оконных функциях может использовать любые методы, рассмотренные выше. Например, быструю сортировку:'

s 1 "EXPLAIN (analyze, buffers, timing off, summary off)
SELECT *, count(*) OVER (ORDER BY seat_no)
FROM seats;"
#s 1 "EXPLAIN (analyze, buffers, timing off, summary off)
#SELECT scheduled_departure, sum(flight_id) OVER (ORDER BY scheduled_departure)
#FROM flights;"

c 'Или внешнюю:'

s 1 "EXPLAIN (analyze, buffers, timing off, summary off)
SELECT *, sum(total_amount) OVER (ORDER BY book_date)
FROM bookings;"

###############################################################################
stop_here
cleanup
demo_end
