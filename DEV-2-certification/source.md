
```sql
CREATE FUNCTION take_task(OUT task tasks) AS $$
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
$$ LANGUAGE plpgsql VOLATILE;


CREATE INDEX ON tasks(task_id) WHERE status = 'scheduled';


CREATE FUNCTION complete_task(task tasks, status text, result text) RETURNS void
LANGUAGE sql VOLATILE
BEGIN ATOMIC
    UPDATE tasks
    SET finished = current_timestamp,
        status = complete_task.status,
        result = complete_task.result
    WHERE task_id = task.task_id;
END;

CREATE PROCEDURE process_tasks() AS $$
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
$$ LANGUAGE plpgsql;

```