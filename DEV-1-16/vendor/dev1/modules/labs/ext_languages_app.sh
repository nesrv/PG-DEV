#!/bin/bash

. ../lib

init 15

start_here

###############################################################################
h '1. Почтовые сообщения'

c 'Простая функция для отправки почтовых сообщений через локальный почтовый сервер может выглядеть так:'

s 1 '\sf sendmail' pgsql

c 'Модуль email дает больше возможностей, но они нам не нужны.'

c 'Создадим фоновое задание для отправки писем:'

s 1 "CREATE FUNCTION public.sendmail_task(params jsonb) RETURNS text
LANGUAGE sql VOLATILE
BEGIN ATOMIC
    SELECT sendmail(
        from_addr => params->>'from_addr',
        to_addr   => params->>'to_addr',
        subj      => params->>'subj',
        msg       => params->>'msg'
    );
    SELECT 'OK';
END;"


s 1 "SELECT register_program('Отправка письма', 'sendmail_task');"
export SENDMAIL=`sudo -i -u $OSUSER psql -A -t -X -d bookstore2 -c "SELECT program_id FROM programs WHERE func = 'sendmail_task'"`

c 'Функция checkout книжного приложения содержит вызов дополнительной функции, куда мы и поместим логику отправки письма:'

s 1 "CREATE OR REPLACE FUNCTION public.before_checkout(user_id bigint)
RETURNS void
AS \$\$
<<local>>
DECLARE
    params jsonb;
BEGIN
    SELECT jsonb_build_object(
        'from_addr', 'bookstore@localhost',
        'to_addr',    u.email,
        'subj',       'Поздравляем с покупкой',
        'msg',        format(
                          E'Уважаемый %s!\\nВы совершили покупку на общую сумму %s ₽.',
                          u.username,
                          sum(ci.qty * get_retail_price(ci.book_id))
                      )
    )
    INTO params
    FROM users u
        JOIN cart_items ci ON ci.user_id = u.user_id
    WHERE u.user_id = before_checkout.user_id
    GROUP BY u.user_id;

    PERFORM empapi.run_program(
        program_id => $SENDMAIL,
        params => params
    );
END;
\$\$ LANGUAGE plpgsql VOLATILE;"

###############################################################################

stop_here
cleanup_app
