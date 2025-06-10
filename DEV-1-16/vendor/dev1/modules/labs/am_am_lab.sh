#!/bin/bash

. ../lib
init

start_here

###############################################################################
h '1. Запрос всех строк таблицы flights'

s 1 "EXPLAIN (analyze, buffers)
SELECT * FROM flights;"

c 'Все страницы прочитаны с диска в общую память (Buffers: shared read=2624). '\
'Возможно, часть страниц была получена из кеша операционной системы, но PostgreSQL об этом ничего не знает.'

c 'Повторим запрос:'

s 1 "EXPLAIN (analyze, buffers)
SELECT * FROM flights;"

c 'Так как мы только что обращались к таблице, в буферном кеше сохранились ее страницы. '\
'Поэтому сервер читает данные из буферного кеша общей памяти (Buffers: shared hit=2624).'

###############################################################################
h '2. Include-индекс для первичного ключа'

c 'Чтобы изменения выполнились атомарно, сделаем их в транзакции.'

s 1 "BEGIN;"

c 'В демонстрации был создан такой include-индекс:'

s 1 'CREATE UNIQUE INDEX tickets_ticket_no_book_ref_idx
ON tickets (ticket_no) INCLUDE (book_ref);'

c 'Теперь индекс tickets_pkey является избыточным и может быть заменен на новый. Для этого удалим старое ограничение целостности (при этом удалится и старый индекс) и добавим новое ограничение, указав имя уже созданного нового индекса. При этом надо учесть наличие внешнего ключа на таблице ticket_flights, которое тоже придется создать заново:'

s 1 "ALTER TABLE tickets DROP CONSTRAINT tickets_pkey CASCADE;"
s 1 "ALTER TABLE tickets ADD CONSTRAINT tickets_pkey PRIMARY KEY USING INDEX tickets_ticket_no_book_ref_idx;"
s 1 "ALTER TABLE ticket_flights
ADD FOREIGN KEY (ticket_no) REFERENCES tickets(ticket_no);"

s 1 "\d tickets"

c 'Вернемся к исходному состоянию:'

s 1 "ROLLBACK;"

###############################################################################
h '3. Выборка 1% строк'

s 1 "CREATE INDEX ON ticket_flights(amount);"

threshold=120000

s 1 "EXPLAIN (analyze)
SELECT * FROM ticket_flights WHERE amount > ${threshold};"

c 'Выбрано сканирование по битовой карте, она уместилась в оперативную память без потери точности.'
c 'Для небольшой выборки сканирование по битовой карте эффективнее, чем последовательное.'

###############################################################################
h '4. Выборка 90% строк'

threshold=42000

s 1 "EXPLAIN (analyze)
SELECT * FROM ticket_flights WHERE amount < ${threshold};"

c 'Запретим последовательное сканирование.'

s 1 "SET enable_seqscan = off;"
s 1 "EXPLAIN (analyze)
SELECT * FROM ticket_flights WHERE amount < ${threshold};"

c 'Точная битовая карта не умещается в оперативную память, во многих страницах пришлось проверять все версии строк.'

c 'Для большой выборки полное сканирование выгоднее.'

c 'Чтобы уменьшить влияние случайных факторов, запросы всегда следует повторять несколько раз, усредняя результаты.'

s 1 "RESET ALL;"
s 1 "DROP INDEX ticket_flights_amount_idx;"

###############################################################################

stop_here
cleanup
demo_end
