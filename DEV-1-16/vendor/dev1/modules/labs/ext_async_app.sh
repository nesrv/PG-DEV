#!/bin/bash

. ../lib

init 13

start_here

###############################################################################
h '1. Реализация обработки очереди заданий'

c 'Функция получения задания из очереди аналогична показанной в демонстрации, но должна учитывать поля таблицы:'

s 1 'SELECT * FROM tasks \gx'

c '(Игнорируйте столбцы host и port — они пригодятся в теме «Обзор физической репликации».)'

s 1 "CREATE FUNCTION take_task(OUT task tasks) AS \$\$
BEGIN
    SELECT *
    INTO task
    FROM tasks
    WHERE status = 'scheduled'
    ORDER BY task_id LIMIT 1
    FOR UPDATE SKIP LOCKED;

    UPDATE tasks
    SET status = 'running',
        started = current_timestamp,
        pid = pg_backend_pid()
    WHERE task_id = task.task_id;
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

c 'Поскольку мы не будем удалять задания из очереди, создадим частичный индекс для эффективного доступа к следующему необработанному заданию:'

s 1 "CREATE INDEX ON tasks(task_id) WHERE status = 'scheduled';"

c 'Функция завершения работы с заданием дополнительно принимает статус завершения и текстовый результат:'

s 1 "CREATE FUNCTION complete_task(task tasks, status text, result text) RETURNS void
LANGUAGE sql VOLATILE
BEGIN ATOMIC
    UPDATE tasks
    SET finished = current_timestamp,
        status = complete_task.status,
        result = complete_task.result
    WHERE task_id = task.task_id;
END;"

c 'Процедура обработки очереди:'

s 1 "CREATE PROCEDURE process_tasks() AS \$\$
DECLARE
    task tasks;
    result text;
    ctx text;
BEGIN
    SET application_name = 'process_tasks';
    <<forever>>
    LOOP
        PERFORM pg_sleep(1);
        SELECT * INTO task FROM take_task();
        COMMIT;
        CONTINUE forever WHEN task.task_id IS NULL;

        BEGIN
            result := empapi.run(task);
            PERFORM complete_task(task, 'finished', result);
        EXCEPTION
            WHEN others THEN
                GET STACKED DIAGNOSTICS
                    result := MESSAGE_TEXT, ctx := PG_EXCEPTION_CONTEXT;
                PERFORM complete_task(
                    task, 'error', result || E'\n' ||  ctx
                );
        END;

        COMMIT;
    END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Обратите внимание, что первая команда COMMIT предшествует команде CONTINUE. В противном случае при отсутствии заданий возникала бы долгая транзакция.'

p

c 'Несколько слов о том, зачем нужна функция run. В принципе, выполнить задание и получить результат можно было бы таким образом:'

s_fake 1 "func := (
    SELECT p.func FROM programs p WHERE p.program_id = task.program_id
);"
s_fake 1 "EXECUTE format(
    \$\$SELECT string_agg(f::text, E'\\n') FROM %I(\$1) AS f\$\$,
    func
)
INTO result
USING task.params;"

c 'К сожалению, PL/pgSQL не позволяет гибко работать со значениями составного типа: у значения неизвестного наперед типа (record) нельзя перебрать все имеющиеся в нем поля. Поэтому для вывода приходится полагаться на стандартное преобразование строки в текст. Это будет некрасиво выглядеть в случае нескольких полей:'

s 1 "SELECT string_agg(f::text, E'\\n') FROM greeting_task() AS f;"

c 'Для аккуратного оформления результата можно воспользоваться другим процедурным языком. Мы используем функцию, написанную на PL/Python. Функция run не вызывается напрямую приложением, но в теме «Обзор физической репликации» мы будем вызывать ее на другом сервере, поэтому она находится в схеме empapi, а не public.'
c 'Подробнее о том, в каких случаях могут пригодиться другие языки, будет рассказано в теме «Языки программирования».'

###############################################################################
h '2. Запуск обработки очереди в фоновом режиме'

c 'В очереди стоит тестовое задание:'

s 1 "SELECT * FROM tasks \gx"

c 'Запускаем обработку (в один поток) и, если все сделано правильно, оно будет выполнено.'

s 1 "SELECT * FROM pg_background_detach(
    pg_background_launch('CALL process_tasks()')
);"

c 'Подождем немного...'

sleep 5

s 1 "SELECT * FROM tasks \gx"

c 'Задание успешно выполнено. Обратите внимание, что результат выполнения содержит и названия столбцов из оригинального запроса.'

c 'Фоновые процессы, обрабатывающие очередь, легко найти благодаря тому, что процедура устанавливает параметр application_name:'

s 1 "SELECT pid, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE application_name = 'process_tasks' \gx"

###############################################################################

stop_here
cleanup_app
