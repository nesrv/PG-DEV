
# Когда фоновое задание завершается ошибкой, оно помечается статусом Error и больше не выполняется.

## Исходные данные
```sql
 CREATE or replace FUNCTION take_task(OUT task tasks) AS $$
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



CREATE or replace FUNCTION complete_task(task tasks, status text, result text) RETURNS void
LANGUAGE sql VOLATILE
BEGIN ATOMIC
    UPDATE tasks
    SET finished = current_timestamp,
        status = complete_task.status,
        result = complete_task.result
    WHERE task_id = task.task_id;
END;



CREATE or replace PROCEDURE process_tasks() AS $$
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

--запуск обработки в один поток
SELECT * FROM pg_background_detach(
    pg_background_launch('CALL process_tasks()')
);

```



```py

   def run (task):
    # получаем параметры задания
    p = plpy.prepare("SELECT func FROM empapi.get_programs() WHERE program_id = $1", ["bigint"])
    r = p.execute([task["program_id"]])
    func = r[0]["func"]
    # выполняем функцию и получаем результат
    p = plpy.prepare("SELECT * FROM " + plpy.quote_ident(func) + "($1)", ["jsonb"])
    r = p.execute([task["params"]])
    # вычисляем максимальную ширину каждого столбца
    cols = r.colnames()
    collen = {col: len(col) for col in cols}
    for i in range(len(r)):
        for col in cols:
            if len( str(r[i][col]) ) > collen[col]:
                collen[col] = len( str(r[i][col]) )
    # выводим названия столбцов с учетом ширины
    res = ""
    res += " ".join( [col.center(collen[col]," ") for col in cols] ) + "\n"
    # отбивка из минусов
    res += " ".join( ["-"*collen[col] for col in cols] ) + "\n"
    # выводим результат
    for i in range(len(r)):
        res += " ".join( [str(r[i][col]).ljust(collen[col]," ") for col in cols] ) + "\n"
    return res


```

```sql
CREATE TABLE tasks (
    task_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    program_id     BIGINT NOT NULL,
    status         TEXT NOT NULL CHECK (status = ANY (ARRAY['scheduled', 'running', 'finished', 'error'])),
    params         JSONB,
    pid            INTEGER,
    started        TIMESTAMPTZ,
    finished       TIMESTAMPTZ,
    result         TEXT,
    host           TEXT,
    port           TEXT,   
    CHECK ((host IS NOT NULL AND port IS NOT NULL) OR (host IS NULL AND port IS NULL))
);
```


Модифицируйте процесс обработки фоновых заданий так, чтобы в случае ошибки механизм пытался выполнить задание заново, но не более трех раз.


в процедуре process_tasks реализовать счет попыток с помощью цикла for in 1...3, без изменения таблицы task
К результату задачи добавьте информацию о номере попытки.



Для проверки обновленного механизма создайте функцию, возвращающую строку 'Мне повезло' только в 30% запусков, а в остальных случаях функция должна завершаться произвольной ошибкой. 

Зарегистрируйте функцию в качестве фонового задания и убедитесь в интерфейсе приложения, что функция не всегда выполняется с первого раза.



```sql
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
            -- Увеличиваем счетчик попыток
            UPDATE tasks SET attempt_count = attempt_count + 1 WHERE task_id = task.task_id;
            -- Получаем обновленное значение счетчика
            SELECT attempt_count INTO task.attempt_count FROM tasks WHERE task_id = task.task_id;
            
            result := empapi.run(task);
            -- Добавляем информацию о номере попытки к результату
            result := result || E'\nПопытка: ' || task.attempt_count;
            PERFORM complete_task(task, 'finished', result);
        EXCEPTION
            WHEN others THEN
                GET STACKED DIAGNOSTICS
                    result := MESSAGE_TEXT, ctx := PG_EXCEPTION_CONTEXT;
                
                -- Проверяем количество попыток
                IF task.attempt_count >= 3 THEN
                    -- Если достигнуто максимальное количество попыток, помечаем задание как ошибочное
                    PERFORM complete_task(
                        task, 'error', 
                        result || E'\nПопытка: ' || task.attempt_count || E'\n' || ctx
                    );
                ELSE
                    -- Иначе возвращаем задание в очередь для повторной попытки
                    PERFORM complete_task(
                        task, 'scheduled', 
                        result || E'\nПопытка: ' || task.attempt_count || E'\n' || ctx
                    );
                END IF;
        END;

        COMMIT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


```

# ! Работает

```sql
CREATE OR REPLACE PROCEDURE process_tasks() AS $$
DECLARE
    task tasks;
    result text;
    ctx text;
    success boolean;
BEGIN
    SET application_name = 'process_tasks';
    <<forever>>
    LOOP
        PERFORM pg_sleep(1);
        SELECT * INTO task FROM take_task();
        COMMIT;
        CONTINUE forever WHEN task.task_id IS NULL;

        success := false;

        FOR attempt IN 1..3 LOOP
            BEGIN
                result := empapi.run(task);
                result := result || E'\n\nПопытка: ' || attempt;
                PERFORM complete_task(task, 'finished', result);
                success := true;
                EXIT; -- Успешно — выходим из попыток
            EXCEPTION
                WHEN others THEN
                    GET STACKED DIAGNOSTICS
                        result := MESSAGE_TEXT, ctx := PG_EXCEPTION_CONTEXT;

                    -- Только если это последняя попытка — сохранить как ошибку
                    IF attempt = 3 THEN
                        result := result || E'\n\nПопытка: ' || attempt;
                        PERFORM complete_task(
                            task, 'error', result || E'\n' || ctx
                        );
                    END IF;
            END;
        END LOOP;

        COMMIT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION test_lucky_function(params jsonb)
RETURNS TABLE(num int, greeting text) AS $$
BEGIN
    -- Принудительно генерируем ошибку в 70% случаев
    IF (random() * 10)::int < 7 THEN
        RAISE EXCEPTION 'Не повезло в этот раз';
    END IF;
    
    -- Если дошли до этой точки, возвращаем успешный результат
    RETURN QUERY SELECT 1 AS num, 'Мне повезло' AS greeting;
END;
$$ LANGUAGE plpgsql;



INSERT INTO programs (name, func) 
VALUES ('test_lucky_function', 'test_lucky_function');

```