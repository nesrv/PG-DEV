
CREATE FUNCTION complete_task(task tasks, status text, result text) RETURNS void
LANGUAGE sql VOLATILE
BEGIN ATOMIC
    UPDATE tasks
    SET finished = current_timestamp,
        status = complete_task.status,
        result = complete_task.result
    WHERE task_id = task.task_id;
END;


CREATE OR REPLACE PROCEDURE process_tasks() AS $$
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
            PERFORM complete_task(task, 'finished123', result || E'\nПопытка: ' || task.attempt_count);
            -- сделать вывод сюда - 'Повезло. Попытка'
        EXCEPTION
            WHEN others THEN
                GET STACKED DIAGNOSTICS
                    result := MESSAGE_TEXT,
                    ctx := PG_EXCEPTION_CONTEXT;

                IF task.attempt_count < 3 THEN
                    -- Увеличиваем счётчик и возвращаем задачу в очередь
                    UPDATE tasks
                    SET
                        status = 'scheduled',
                        attempt_count = attempt_count + 1,
                        result = result || E'\nПопытка: ' || task.attempt_count || E'\n' || ctx
                    WHERE task_id = task.task_id;
                ELSE
                    -- Превышен лимит попыток — ошибка
                    PERFORM complete_task(
                        task, 'error',
                        result || E'\nПопытка: ' || task.attempt_count || E'\n' || ctx
                    );
                END IF;
        END;
        COMMIT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION is_lucky_2(params jsonb)
RETURNS TABLE(num int, greeting text) AS $$
BEGIN
    IF random() < 0.3 THEN
        RETURN QUERY SELECT 1 AS num, 'Мне повезло' AS greeting; -- отдать результат в  PROCEDURE process_tasks

    ELSE
        RAISE EXCEPTION 'Не повезло :(';
    END IF;
END;
$$ LANGUAGE plpgsql;






INSERT INTO programs (name, func)
VALUES ('Ловец удачи', 'is_lucky_2');


 SELECT * FROM pg_background_detach(
    pg_background_launch('CALL process_tasks()')
);





