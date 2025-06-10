#!/bin/bash

. ../lib

init

psql_open A 2

start_here 7

###############################################################################
h 'Очередь средствами расширения pgmq'

c 'Создадим базу данных и подключимся к ней:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Расширение pgmq уже собрано и доступно для установки. Выполним команду создания расширения в нашей базе. Все его объекты будут размещены в схеме pgmq:'

s 1 'CREATE EXTENSION pgmq;'

c 'Создадим очередь под названием pgmq_queue:'

s 1 "SELECT pgmq.create('pgmq_queue');"

c 'Информация об очередях хранится в таблице meta; посмотреть очереди можно с помощью табличной функции:'
s 1 'SELECT * FROM pgmq.list_queues();'

c 'Также были созданы таблицы для сообщений очереди: основная q_pgmq_queue и архивная a_pgmq_queue:'

s 1 '\dt pgmq.*'

c 'Поместим в очередь несколько сообщений (полезная информация представляется значением типа jsonb)...'

s 1 "SELECT pgmq.send('pgmq_queue', to_jsonb(i))
FROM (
    VALUES ('alpha'), ('beta'), ('gamma')
) AS v(i);"

c '...и заглянем в основную таблицу очереди:'

s 1 'SELECT msg_id, enqueued_at, message 
FROM pgmq.q_pgmq_queue 
ORDER BY msg_id;'

c 'Простой способ забрать сообщение из очереди — вызвать функцию pop:'

s 1 "SELECT msg_id, enqueued_at, message
FROM pgmq.pop('pgmq_queue');"

c 'Другие обработчики тоже могут брать сообщения:'

psql_open A 2 -d "$TOPIC_DB"
s 2 "SELECT msg_id, enqueued_at, message
FROM pgmq.pop('pgmq_queue');"

psql_open A 3 -d "$TOPIC_DB"
s 3 "SELECT msg_id, enqueued_at, message
FROM pgmq.pop('pgmq_queue');"

c 'А первый при очередном обращении обнаружит, что очередь пуста:'
s 1 "SELECT msg_id, enqueued_at, message
FROM pgmq.pop('pgmq_queue');"

p

c 'И напоследок удалим саму очередь. При этом ее основная и архивная таблицы исчезнут, как и информация в таблице meta:'

s 1 "SELECT pgmq.drop_queue('pgmq_queue');"
s 1 '\dt pgmq.*'

P 9

###############################################################################
h 'Реализация очереди сообщений'

c 'Наша задача: реализовать простую очередь сообщений с возможностью конкурентного получения сообщений из нескольких процессов. Полезную информацию снова представим типом JSON — так очередь будет достаточно универсальна.'

c 'В каждый конкретный момент времени в таблице сообщений не будет много строк, но за все время работы их может оказаться существенное количество. Поэтому идентификатор надо сразу сделать 64-разрядным:'


s 1 "CREATE TABLE msg_queue(
    id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    payload jsonb NOT NULL,
    pid integer DEFAULT NULL -- процесс-обработчик
);"

c 'Вставка сообщений в очередь проста:'

s 1 "INSERT INTO msg_queue(payload)
VALUES
    (to_jsonb(1)),
    (to_jsonb(2)),
    (to_jsonb(3));"

p

c 'Теперь займемся функцией получения и блокирования очередного сообщения.'

c 'Нам требуется блокировать полученную строку, чтобы одно сообщение не могло быть выбрано два раза (двумя одновременно работающими обработчиками). Это можно сделать с помощью фразы FOR UPDATE:'

s 1 "BEGIN;"
s 1 "SELECT * FROM msg_queue
WHERE pid IS NULL -- никем не обрабатывается
ORDER BY id LIMIT 1 -- одно в порядке поступления
FOR UPDATE;"

c 'Но в таком случае аналогичный запрос в другом процессе будет заблокирован до завершения первой транзакции.'

s 2 "\c $TOPIC_DB"
s 2 "BEGIN;"
ss 2 "SELECT * FROM msg_queue
WHERE pid IS NULL
ORDER BY id LIMIT 1
FOR UPDATE;"
sleep 1

c 'Вторая транзакция заблокирована.'

s 1 "DELETE FROM msg_queue
WHERE id = 1;"
s 1 "COMMIT;"
r 2
s 2 "COMMIT;"

c 'Для того чтобы не останавливаться на заблокированных строках, служит фраза SKIP LOCKED команды SELECT.'

s 1 "BEGIN;"
s 1 "SELECT * FROM msg_queue
WHERE pid IS NULL
ORDER BY id LIMIT 1
FOR UPDATE SKIP LOCKED;"

s 2 "BEGIN;"
s 2 "SELECT * FROM msg_queue
WHERE pid IS NULL
ORDER BY id LIMIT 1
FOR UPDATE SKIP LOCKED;"

s 1 "COMMIT;"
s 2 "COMMIT;"

c 'Итак, функция для получения и блокирования очередного сообщения может выглядеть следующим образом:'

s 1 "CREATE FUNCTION take_message(OUT msg msg_queue)
LANGUAGE sql VOLATILE
BEGIN ATOMIC
    UPDATE msg_queue
    SET pid = pg_backend_pid()
    WHERE id = (SELECT id FROM msg_queue
	WHERE pid IS NULL
        ORDER BY id LIMIT 1
	FOR UPDATE SKIP LOCKED) RETURNING *;
END;"

p

c 'В практических заданиях к темам «Очистка» и «Фоновые задания» мы рассматривали типичное решение для получения пакета строк таблицы, например, с целью обновления или удаления. Запрос выглядел так:'

s_fake 1 "WITH batch AS (
    SELECT * FROM t
    WHERE /* необходимые условия */
    LIMIT /* размер пакета */
    FOR UPDATE SKIP LOCKED
)
..."

c 'Как видите, в обоих случаях используется тот же самый подход: выбирается и блокируется часть строк (одна или несколько), при этом уже заблокированные строки пропускаются.'

p

c 'Теперь напишем функцию завершения работы с сообщением. Мы будем просто удалять его из очереди.'

s 1 "CREATE FUNCTION complete_message(msg msg_queue) RETURNS void
LANGUAGE sql VOLATILE
BEGIN ATOMIC
  DELETE FROM msg_queue WHERE id = msg.id;
END;"

p

c 'Теперь мы готовы написать цикл обработки сообщений. Оформим его в виде процедуры.'

s 1 "CREATE PROCEDURE process_queue() AS \$\$
DECLARE
    msg msg_queue;
BEGIN
    LOOP
        SELECT * INTO msg FROM take_message();
        EXIT WHEN msg.id IS NULL;

        -- обработка
        PERFORM pg_sleep(1);
        RAISE NOTICE '[%] processed %; n_tup_del=%, backend_xmin=%',
            pg_backend_pid(),
            msg.payload,

            (SELECT n_tup_del FROM pg_stat_xact_all_tables  -- статистика, накопленная внутри транзакции
             WHERE relname = 'msg_queue'),

            (SELECT backend_xmin FROM pg_stat_activity
             WHERE pid = pg_backend_pid());

        PERFORM complete_message(msg);
    END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'В этом варианте цикл заканчивается, когда в очереди не остается необработанных сообщений. Вместо этого можно не прекращать цикл, но продолжать ожидать новые события, засыпая, например, на одну секунду.'

c 'Пробуем.'

s 1 "CALL process_queue();"

c 'Теперь в два потока.'

s 1 "INSERT INTO msg_queue(payload)
SELECT to_jsonb(id) FROM generate_series(1,10) id;"

s 1 '\timing on'
ssi 1 "CALL process_queue();"
ssi 2 "CALL process_queue();"
r 2
r 1
s 1 '\timing off'

c 'Обработка 10 сообщений двумя потоками заняла около 5 секунд, но горизонт транзакций держался на одном уровне все время обработки очереди! Это будет мешать выполнению очистки и создавать проблемы для всей базы данных.'

P 13

###############################################################################
h 'Учитываем горизонт транзакций'

c 'Это легко сделать, поскольку процедура позволяет управлять транзакциями.'

s 1 "CREATE OR REPLACE PROCEDURE process_queue() AS \$\$
DECLARE
    msg msg_queue;
BEGIN
    LOOP
        SELECT * INTO msg FROM take_message();
        COMMIT; --<<
        EXIT WHEN msg.id IS NULL;

        -- обработка
        PERFORM pg_sleep(1);
        RAISE NOTICE '[%] processed %; n_dead_tup=%, n_tup_del=%, backend_xmin=%',
            pg_backend_pid(),
            msg.payload,

            (SELECT n_dead_tup FROM pg_stat_all_tables  -- статистика, учитываемая автоочисткой
             WHERE relname = 'msg_queue'),

            (SELECT n_tup_del FROM pg_stat_xact_all_tables
             WHERE relname = 'msg_queue'),

            (SELECT backend_xmin FROM pg_stat_activity
             WHERE pid = pg_backend_pid());

        PERFORM complete_message(msg);
        COMMIT; --<<
    END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Проверим:'

s 1 "INSERT INTO msg_queue(payload)
SELECT to_jsonb(id) FROM generate_series(1,5) id;"

s_bare 1 "SELECT pg_stat_reset_single_table_counters('msg_queue'::regclass);"

s 1 "CALL process_queue();"

c 'Теперь горизонт транзакций продвигается вперед и не мешает очистке. Однако момент срабатывания автоматической очистки определяется на основе данных статистики, которая обновляется лишь по окончании работы всего оператора CALL.'

s 1 "SELECT n_dead_tup, n_live_tup, n_mod_since_analyze, n_ins_since_vacuum 
FROM pg_stat_all_tables 
WHERE relname = 'msg_queue';"

c 'Таким образом, чтобы таблица с очередью вовремя очищалась, можно:'
ul 'модифицировать процедуру process_queue таким образом, чтобы обеспечить ее гарантированное периодическое завершение и положиться на автоочистку;'
ul 'периодически запускать обычную (неавтоматическую) очистку. Один из способов реализации — использование фоновых процессов, которые рассмотрены в соответствующей теме этого курса.'

###############################################################################

stop_here
cleanup
demo_end
