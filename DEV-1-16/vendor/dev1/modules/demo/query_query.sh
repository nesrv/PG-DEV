#!/bin/bash

. ../lib
init

start_here 13
###############################################################################

h 'Простой протокол'

c 'Простой протокол запросов применяется, когда на сервер отправляется оператор и, '\
'если это SELECT или команда с фразой RETURNING, мы ожидаем получение всех строк результата. Например:'

s 1 "SELECT model FROM aircrafts WHERE aircraft_code = '773';"

c 'Обычный удобный способ получить план запроса — команда EXPLAIN (пока отключаем вывод стоимости): '

s 1 "EXPLAIN (buffers, costs off)
SELECT * FROM airports;"

c 'Если задан параметр buffers, в поле Planning Buffers будет показано число страниц буферного кеша, которое было прочитано при построении плана.'

c 'Если добавить параметр analyze, сервер выполнит запрос и отобразит его план с детальной информацией о выполнении. Будьте аккуратны с запросами, изменяющими данные!'

s 1 "EXPLAIN (analyze, buffers, costs off)
SELECT * FROM airports;"

c 'В поле Buffers отображается тип кеша (shared — буферный кеш в общей памяти) и количество страниц:'
ul 'hit     — найденных в кеше;'
ul 'read    — не найденных в кеше и запрошенных у операционной системы;'
ul 'written — записанных в файлы;'
ul 'dirtied — ставших грязными (т.е. впервые измененных в кеше).'

p

c 'Теперь создадим временную таблицу и вставим в нее строки таблицы airports:'

s 1 "CREATE TEMP TABLE temp_airports (LIKE airports);"
s 1 "EXPLAIN (analyze, buffers, costs off)
INSERT INTO temp_airports SELECT * FROM airports;"

c 'Временная таблица кешируется в локальной памяти сеанса (Buffers ... local).'

c 'Предупреждение: вывод времени выполнения каждого шага, как в этом примере, может существенно замедлять выполнение запроса на некоторых платформах. Если такая информация не нужна, лучше указывать timing off.'

P 16

###############################################################################

h 'JIT-компиляция'

c 'По умолчанию JIT-компиляция включена, но для демобазы она выключена:'

s 1 "SELECT setconfig
FROM pg_db_role_setting
WHERE setdatabase = (SELECT oid FROM pg_database WHERE datname='demo');"

s 1 "SELECT name, setting, boot_val
FROM pg_settings
WHERE name='jit';"

c 'Выполним запрос, рассчитывающий значение числа π. В запросе активно используются вычисления, которые JIT может оптимизировать:'

s 1 "SET jit = on;"

s 1 "WITH pi AS (
  SELECT random() x, random() y 
  FROM generate_series(1,10_000_000)
)
SELECT 4*sum(1-floor(x*x+y*y))/count(*) val FROM pi;"

c 'Команда EXPLAIN ANALYZE покажет подробную информацию о том, какие оптимизации JIT сработали:'
 
s 1 "EXPLAIN (analyze, timing off)
WITH pi AS (
  SELECT random() x, random() y 
  FROM generate_series(1,10_000_000)
)
SELECT 4*sum(1-floor(x*x+y*y))/count(*) val FROM pi;"

c 'Выключим JIT-компиляцию и повторим запрос:'

s 1 "SET jit = off;"

s 1 "EXPLAIN (analyze, timing off)
WITH pi AS (
  SELECT random() x, random() y 
  FROM generate_series(1,10_000_000)
)
SELECT 4*sum(1-floor(x*x+y*y))/count(*) val FROM pi;"

c 'Время выполнения запроса, скорее всего, немного увеличивается.'

c 'В рамках курса мы не будем подробно рассматривать оптимизации JIT. Чтобы сообщения о JIT-компиляции не загромождали планы запросов, на уровне демобазы JIT отключен.'

P 21

###############################################################################

h 'Подготовленные операторы'

c 'Создадим подготовленный оператор для запроса с параметром:'

s 1 "PREPARE model(varchar) AS
  SELECT model FROM aircrafts WHERE aircraft_code = \$1;"

c 'Теперь мы можем вызывать оператор по имени:'

s 1 "EXECUTE model('773');"
s 1 "EXECUTE model('763');"

c 'Все подготовленные операторы можно увидеть в представлении:'

s 1 "SELECT * FROM pg_prepared_statements \gx"

ul 'name — имя подготовленного оператора,'
ul 'statement — создавшая его команда,'
ul 'prepare_time — момент создания,'
ul 'parameter_types — типы параметров (массив),'
ul 'result_types — типы столбцов результата (массив),'
ul 'from_sql — оператор создан командой SQL PREPARE (а не вызовом функции драйвера),'
ul 'generic_plans — сколько раз использовался общий план,'
ul 'custom_plans — сколько раз строились и использовались частные планы.'

c 'Если подготовленный оператор больше не нужен, его можно удалить командой DEALLOCATE, но в любом случае оператор пропадет при завершении сеанса.'

s 1 "\c"
s 1 "SELECT * FROM pg_prepared_statements \gx"

c 'Команды PREPARE, EXECUTE, DEALLOCATE — команды SQL. Клиенты на других языках программирования будут использовать операции, определенные в соответствующем драйвере. Но любой драйвер использует один и тот же протокол для взаимодействия с сервером.'

c 'Если в psql выполнить запрос с параметрами, он будет использовать расширенный протокол запросов. '\
' В этом случае нужно предварительно задать значения параметров:'
s 1 "\bind '773'"

c 'Подготовленный оператор будет создан неявно.'
s 1 "SELECT model FROM aircrafts WHERE aircraft_code = \$1;"

c 'После выполнения запроса подготовленный оператор удаляется:'
s 1 "SELECT * FROM pg_prepared_statements \gx"

c 'Значения параметров после выполнения сбрасываются, поэтому задавать их нужно перед каждым запросом:'
s 1 "\bind '763'"
s 1 "EXPLAIN SELECT model FROM aircrafts WHERE aircraft_code = \$1;"

c 'Такой подход можно использовать, если нужно отладить выполнение запроса с расширенным протоколом.'

p

###############################################################################

h 'Курсоры'

c 'Курсоры дают возможность построчной обработки результата. Они часто используются в приложениях и имеют особенности, связанные с оптимизацией.'
c 'На SQL использование курсоров можно продемонстрировать следующим образом. Объявляем курсор (при этом он сразу же открывается) и выбираем первую строку:'

s 1 'BEGIN;'
s 1 'DECLARE c CURSOR FOR SELECT * FROM aircrafts;'
s 1 'FETCH c;'

c 'Читаем вторую строку результата и закрываем открытый курсор (курсор закроется и автоматически по окончании транзакции):'

s 1 'FETCH c;'
s 1 'CLOSE c;'
s 1 'COMMIT;'

###############################################################################
stop_here
cleanup
demo_end
