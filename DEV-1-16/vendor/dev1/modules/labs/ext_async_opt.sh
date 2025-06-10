#!/bin/bash

. ../lib

init

psql_open A 2

start_here

###############################################################################
h '1. Тестирование реализации очереди'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Повторим реализацию очереди, показанную в демонстрации.'

c 'Таблица:'

s 1 "CREATE TABLE msg_queue(
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payload jsonb NOT NULL,
  pid integer DEFAULT NULL
);"

c 'Функция получения и блокирования очередного сообщения:'

s 1 "CREATE FUNCTION take_message(OUT msg msg_queue) AS \$\$
BEGIN
    SELECT *
    INTO msg
    FROM msg_queue
    WHERE pid IS NULL
    ORDER BY id LIMIT 1
    FOR UPDATE SKIP LOCKED;

    UPDATE msg_queue
    SET pid = pg_backend_pid()
    WHERE id = msg.id;
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

c 'Функция завершения работы с сообщением:'

s 1 "CREATE FUNCTION complete_message(msg msg_queue) RETURNS void
LANGUAGE sql VOLATILE
BEGIN ATOMIC 
    DELETE FROM msg_queue WHERE id = msg.id;
END;"


c 'В процедуру обработки очереди внесем изменение: вместо секундной задержки будем записывать информацию об обрабатываемом сообщении в отдельную таблицу:'

s 1 "CREATE TABLE msg_log(
    id bigint,
    pid integer
);"

s 1 "CREATE PROCEDURE process_queue() AS \$\$
DECLARE
    msg msg_queue;
BEGIN
    LOOP
        SELECT * INTO msg FROM take_message();
        EXIT WHEN msg.id IS NULL;
        COMMIT;

        -- обработка
        INSERT INTO msg_log(id, pid) VALUES (msg.id, pg_backend_pid());

        PERFORM complete_message(msg);
        COMMIT;
    END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Создаем большое количество сообщений:'

s 1 "INSERT INTO msg_queue(payload)
SELECT to_jsonb(id) FROM generate_series(1,1000) id;"

c 'Запускаем обработку в два потока, засекая время:'

psql_open A 2 $TOPIC_DB
s 1 '\timing on'
ss 1 "CALL process_queue();"
ssi 2 "CALL process_queue();"
r 2
r 1
s 1 '\timing off'

c 'Проанализируем результаты. При корректной работе мы должны обнаружить в журнальной таблице ровно 1000 уникальных идентификаторов, что будет означать, что обработаны все события, и ни одно не обработано дважды.'

s 1 "SELECT count(*), count(DISTINCT id) FROM msg_log;"

c 'Все корректно.'

p

c 'Проверим теперь реализацию без предложения FOR UPDATE SKIP LOCKED.'

s 1 "CREATE OR REPLACE FUNCTION take_message(OUT msg msg_queue) AS \$\$
BEGIN
    SELECT *
    INTO msg
    FROM msg_queue
    WHERE pid IS NULL
    ORDER BY id LIMIT 1
    /*FOR UPDATE SKIP LOCKED*/;

    UPDATE msg_queue
    SET pid = pg_backend_pid()
    WHERE id = msg.id;
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

s 1 "TRUNCATE msg_queue;"
s 1 "TRUNCATE msg_log;"

s 1 "INSERT INTO msg_queue(payload)
SELECT to_jsonb(id) FROM generate_series(1,1000) id;"

c 'Запускаем обработку:'

s 1 '\timing on'
ss 1 "CALL process_queue();"
ssi 2 "CALL process_queue();"
r 1
r 2
s 1 '\timing off'

s 1 "SELECT count(*), count(DISTINCT id) FROM msg_log;"

c 'Как видим, часть сообщений была обработана дважды. Например:'

s 1 "SELECT id, array_agg(pid) FROM msg_log
GROUP BY id HAVING count(*) > 1
LIMIT 10;"

c 'Это произошло из-за того, что сообщение, обрабатываемое одним процессом, никак не блокируется и доступно для другого процесса.'

p

c 'Восстановим корректную функцию:'

s 1 "CREATE OR REPLACE FUNCTION take_message(OUT msg msg_queue) AS \$\$
BEGIN
    SELECT *
    INTO msg
    FROM msg_queue
    WHERE pid IS NULL
    ORDER BY id LIMIT 1
    FOR UPDATE SKIP LOCKED;

    UPDATE msg_queue
    SET pid = pg_backend_pid()
    WHERE id = msg.id;
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

###############################################################################
h '2. Обработка зависших сообщений'

c 'Мы можем перехватить ошибку, возникающую при обработке события, но тем не менее всегда есть шанс того, что сама процедура-обработчик завершится аварийно. Сымитируем такую ситуацию:'

s 1 "TRUNCATE msg_queue;"
s 1 "TRUNCATE msg_log;"

s 1 "INSERT INTO msg_queue(payload)
SELECT to_jsonb(id) FROM generate_series(1,1000) id;"

c 'Запускаем обработку...'

ss 2 "CALL process_queue();"

c '...а в это время в другом сеансе:'

wait_sql 1 "SELECT count(*)>0 FROM msg_log;"
si 1 "BEGIN;"
si 1 "LOCK TABLE msg_log;"
sleep 1
si 1 "SELECT pid, pg_terminate_backend(pid) FROM msg_log LIMIT 1;"
si 1 "COMMIT;"

tolerate_lostconn=true
r 2
tolerate_lostconn=false

c 'Обработчик «упал». Причем, благодаря команде LOCK TABLE, — сразу после того, как зафиксировал номер процесса в таблице очереди. В очереди остались необработанные сообщения и среди них — одно зависшее:'

s 1 "SELECT count(*), count(DISTINCT id) FROM msg_log;"
s 1 "SELECT * FROM msg_queue WHERE pid IS NOT NULL;"

c 'Самый простой способ исправить ситуацию — изменить функцию выбора сообщения:'

s 1 "CREATE OR REPLACE FUNCTION take_message(OUT msg msg_queue) AS \$\$
BEGIN
    SELECT *
    INTO msg
    FROM msg_queue
    WHERE pid IS NULL OR pid NOT IN (SELECT pid FROM pg_stat_activity)
    ORDER BY id LIMIT 1
    FOR UPDATE SKIP LOCKED;

    UPDATE msg_queue
    SET pid = pg_backend_pid()
    WHERE id = msg.id;
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

c 'Если события обрабатываются быстро и важна высокая пропускная способность, то проверку лучше выполнять отдельно и только время от времени, чтобы избежать постоянного обращения к pg_stat_activity.'

c 'Снова запустим обработчик, и все сообщения, включая зависшее, будут обработаны.'

s 1 "CALL process_queue();"

s 1 "SELECT count(*), count(DISTINCT id) FROM msg_log;"

###############################################################################

stop_here
cleanup
