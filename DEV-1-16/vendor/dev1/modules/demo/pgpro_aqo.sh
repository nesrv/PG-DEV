#!/bin/bash

. ../lib
init

start_here 4

###############################################################################
h 'Пример запроса с неверной оценкой.'

c 'Начнем с установки расширения.'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'aqo';"

c 'Необходима перезагрузка экземпляра.'
pgctl_restart A
psql_open A 1 demo

c 'Добавим расширение AQO в базу данных:'
s 1 'CREATE EXTENSION aqo;'

c 'В качестве примера мы будем использовать запрос с ошибкой вычисления кардинальности, вызванной коррелированными предикатами.'

s 1 "EXPLAIN SELECT *
FROM flights fl
  JOIN airports ap ON ( fl.departure_airport = ap.airport_code )
WHERE ap.airport_name = 'Внуково'
  AND fl.flight_no = 'PG0007';"

c 'Точное количество строк отличается от оценки:'

s 1 "SELECT count(*)
FROM flights fl
  JOIN airports ap ON ( fl.departure_airport = ap.airport_code )
WHERE ap.airport_name = 'Внуково'
  AND fl.flight_no = 'PG0007';"

c 'Причина неверной оценки в том, что рейс PG0007 всегда вылетает из Внуково. Но планировщику это не известно.'
c 'В курсе QPT продемонстрировано использование расширенной статистики по функциональным зависимостям, исправляющей неверную оценку кардинальности. В этой теме для исправления неверной оценки будет использован модуль AQO.'

###############################################################################
P 9
h 'Режим learn'

c 'Переключим режим работы AQO:'
s 1 "SET aqo.mode = 'learn';"

c 'Для удобства включим параметры детализации и вывода хешей запросов:'
s 1 "SET aqo.show_hash = on;"
s 1 "SET aqo.show_details = on;"

c 'Уменьшим значение параметра aqo.join_threshold (значение по умолчанию — 3). AQO игнорирует запросы, содержащие меньшее количество соединений.'
s 1 "SET aqo.join_threshold = 1;"

c 'Выполним показанный ранее запрос:'
s 1 "EXPLAIN ANALYZE SELECT *
FROM flights fl
  JOIN airports ap ON ( fl.departure_airport = ap.airport_code )
WHERE ap.airport_name = 'Внуково'
  AND fl.flight_no = 'PG0007';"

c 'Для AQO этот запрос является новым, поэтому для планирования использовались обычные оценки. Но AQO уже получил данные для обучения модели:'

QRYID1=`s_bare 1 "SELECT queryid AS QRYID1 FROM aqo_query_texts WHERE query_text ~ 'ap.airport_name = ''Внуково';"`
s 1 "SELECT * FROM aqo_query_texts WHERE query_text ~ 'ap.airport_name = ''Внуково' \gx"
s 1 "SELECT * FROM aqo_query_stat WHERE queryid = $QRYID1 \gx"

c 'Выполним запрос еще раз. Теперь уже будет использована уточненная оценка:'

s 1 "EXPLAIN ANALYZE SELECT *
FROM flights fl
  JOIN airports ap ON ( fl.departure_airport = ap.airport_code )
WHERE ap.airport_name = 'Внуково' AND fl.flight_no = 'PG0007';"

c 'Оценка кардинальности исправилась.'

c 'В статистике по классу количество выполнений с AQO должно увеличиться.'
s 1 "SELECT * FROM aqo_query_stat WHERE queryid = $QRYID1 \gx"

c 'Новая оценка будет применяться и к другим запросам того же класса, например, с другим номером рейса:'

s 1 "EXPLAIN ANALYZE SELECT *
FROM flights fl
  JOIN airports ap ON fl.departure_airport = ap.airport_code
WHERE ap.airport_name = 'Внуково'
  AND fl.flight_no = 'PG0025';"

c 'Обратите внимание, что запрос классифицируется исходя из дерева разбора, поэтому AQO не чувствителен к таким изменениям текста, как регистр, переносы строк и т. п.'

###############################################################################
P 11
h 'Режим controlled'

c 'Вернем AQO в режим по умолчанию controlled.'
s 1 "RESET aqo.mode;"

c 'Снова выполним наш запрос:'

s 1 "EXPLAIN ANALYZE SELECT *
FROM flights fl
  JOIN airports ap ON ( fl.departure_airport = ap.airport_code ) 
WHERE ap.airport_name = 'Внуково'
  AND fl.flight_no = 'PG0007';"

c 'AQO используется, так как запрос принадлежит уже известному классу запросов (Using aqo: true).'

c 'Свойства этого класса запросов:'

s 1 "SELECT queryid, learn_aqo, use_aqo
FROM aqo_queries
WHERE queryid = $QRYID1;"

c 'Выполним похожий запрос, в котором вместо поиска по равенству использован поиск по регулярному выражению (символ тильды):'

s 1 "EXPLAIN ANALYZE SELECT *
FROM flights fl
  JOIN airports ap ON ( fl.departure_airport = ap.airport_code ) 
WHERE ap.airport_name ~ 'Внуково'
  AND fl.flight_no = 'PG0007';"

c 'В режиме controlled новые запросы не классифицируются AQO (обратите внимание, что в узлах плана запроса отсутствуют строки, соответствующие AQO).'

c 'Запретим использование AQO для запроса с равенством:'

s 1 "SELECT aqo_disable_class($QRYID1);"
s 1 "SELECT queryid, learn_aqo, use_aqo
FROM aqo_queries
WHERE queryid = $QRYID1;"

c 'Теперь AQO не будет собирать статистику и не будет использоваться для улучшения оценок этого класса запросов:'

s 1 "EXPLAIN ANALYZE SELECT *
FROM flights fl
  JOIN airports ap ON ( fl.departure_airport = ap.airport_code ) 
WHERE ap.airport_name = 'Внуково'
  AND fl.flight_no = 'PG0007';"

###############################################################################

stop_here
cleanup
demo_end
