#!/bin/bash

. ../lib

init 18

# Базовые объекты уже созданы (ext_bgworkers_app.sh)

backup_dir=/home/$OSUSER/backup
e "rm -rf $backup_dir"

start_here

###############################################################################
h '1. Развертывание реплики'

c 'Выполняем те же команды, что и в демонстрации.'

e_fake "pg_basebackup --pgdata=$backup_dir -R"
pg_basebackup --pgdata=$backup_dir -R --checkpoint=fast

pgctl_stop R
e "sudo rm -rf $PGDATA_R"
e "sudo mv $backup_dir $PGDATA_R"
e "sudo chown -R postgres: $PGDATA_R"

pgctl_start R

c 'При переключении приложения на реплику:'

ul 'Поиск книг и другие операции, не требующие изменения данных, работают;'
ul 'Вход, покупка книг и другие операции, изменяющие данные, выдают ошибку.'

###############################################################################
h '2. Фоновые задания в удаленном режиме'

c 'Добавим в процедуру запуска задания обработку узла и порта. Если они указаны, будем выполнять функцию run на указанном сервере с помощью расширения dblink. За основу берем вариант процедуры, написанной в практике к теме «Асинхронная обработка».'

s 1 "CREATE EXTENSION IF NOT EXISTS dblink;"

s 1 "CREATE OR REPLACE PROCEDURE process_tasks() AS \$\$
DECLARE
    task tasks;
    result text;
    ctx text;
BEGIN
    SET application_name = 'process_tasks';
    <<forever>>
    LOOP
        COMMIT;
        PERFORM pg_sleep(1);
        SELECT * INTO task FROM take_task();
        COMMIT;
        CONTINUE forever WHEN task.task_id IS NULL;

        IF task.host IS NULL THEN -- запускаем локально
            BEGIN
                result := empapi.run(task);
                PERFORM complete_task(task, 'finished', result);
            EXCEPTION
                WHEN others THEN
                    GET STACKED DIAGNOSTICS
                        result := MESSAGE_TEXT,
                        ctx := PG_EXCEPTION_CONTEXT;
                    PERFORM complete_task(
                        task, 'error', result || E'\n' ||  ctx
                    );
            END;
        ELSE -- запускаем удаленно в асинхронном режиме
            BEGIN
                PERFORM dblink_connect(
                    'remote',
                    format(
                        'host=%s port=%s dbname=%s user=%s password=%s',
                        task.host, task.port, 'bookstore2', 'student', 'student'
                    )
                );
            EXCEPTION
                WHEN others THEN
                    GET STACKED DIAGNOSTICS
                        result := MESSAGE_TEXT,
                        ctx := PG_EXCEPTION_CONTEXT;
                    PERFORM complete_task(
                        task, 'error', result || E'\n' ||  ctx
                    );
                    CONTINUE forever;
            END;
            PERFORM dblink_send_query(
                'remote',
                format('SELECT * FROM empapi.run(%L)', task)
            );
            -- ожидание результата
            LOOP
                PERFORM pg_sleep(1);
                EXIT WHEN (SELECT dblink_is_busy('remote')) = 0;
                COMMIT;
            END LOOP;
            -- получение результата
            BEGIN
                SELECT s INTO result
                FROM dblink_get_result('remote') AS (s text);
                PERFORM complete_task(task, 'finished', result);
            EXCEPTION
                WHEN others THEN
                    GET STACKED DIAGNOSTICS
                        result := MESSAGE_TEXT,
                        ctx := PG_EXCEPTION_CONTEXT;
                    PERFORM complete_task(
                        task, 'error', result || E'\n' ||  ctx
                    );
            END;
            PERFORM dblink_disconnect('remote');
        END IF;
    END LOOP;
END;
\$\$ LANGUAGE plpgsql;"

c 'Обратите внимание на следующее:'
ul 'Для краткости не обрабатывается статус вызова функции dblink_send_query, что, конечно же, необходимо делать.'
ul 'В цикле ожидания результатов удаленного запуска выполняется фиксация. В противном случае получалась бы долгая транзакция, удерживающая горизонт базы данных.'
ul 'Дублируется код для обработки исключительных ситуаций. Это связано с тем, что процедура не может выполнять фиксацию внутри блока с секцией EXCEPTION.'
ul 'Команда COMMIT перенесена из конца цикла forever в начало. Это сделано для удобства прерывания обработки в случае ошибки (см. обработчик dblink_connect).'

p

c 'Работающий в системе фоновый процесс, выполняющий процедуру process_tasks, будет продолжать выполнять старую версию процедуры. Его необходимо прервать и перезапустить:'

s 1 "SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE application_name = 'process_tasks';"
s 1 "SELECT * FROM pg_background_detach(
    pg_background_launch('CALL process_tasks()')
);"

###############################################################################

stop_here
cleanup_app
