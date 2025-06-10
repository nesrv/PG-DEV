
* process_task

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
            result := empapi.run(task);
            PERFORM complete_task(task, 'finished', result || E'\nПопытка: ' || task.attempt_count);
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

```




#### 2. **Создайте функцию `is_lucky_2(jsonb)`**, которая принимает параметр `jsonb` и работает аналогично `is_lucky`, но с нужной сигнатурой:

```sql
CREATE OR REPLACE FUNCTION is_lucky_2(params jsonb)
RETURNS TABLE(num int, greeting text) AS $$
BEGIN
    IF random() < 0.3 THEN
        RETURN QUERY SELECT 1 AS num, 'Мне повезло' AS greeting;
    ELSE
        RAISE EXCEPTION 'Не повезло :(';
    END IF;
END;
$$ LANGUAGE plpgsql;
```

> Функция возвращает таблицу, как ожидается функцией `empapi.run`, и принимает `jsonb`, как требуется в PL/Python коде.

---

#### 2. **Проверьте, что в таблице `programs` функция зарегистрирована корректно:**

```sql
INSERT INTO programs (name, func)
VALUES ('Ловец удачи', 'is_lucky_2');
```

> Не забудьте, что `func` — это имя SQL-функции без скобок, передаваемой в `empapi.run`.

---

Теперь после запуска фоновой процедуры:

```sql
CALL process_tasks();
```

задание должно выполняться с 30% вероятностью успеха, с 3 попытками в случае ошибки.

