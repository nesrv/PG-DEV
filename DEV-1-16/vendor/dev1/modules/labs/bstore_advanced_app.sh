#!/bin/bash

sudo service pgbouncer restart  # сбросить соединения

. ../lib

init

start_here

###############################################################################

h '1. Удаление сеансов'

c 'Добавим в функцию входа удаление существующих сеансов:'

s 1 "CREATE OR REPLACE FUNCTION webapi.login(username text) RETURNS uuid
AS \$\$
DECLARE
    auth_token uuid;
    sessions record;
BEGIN
    -- сначала завершим все открытые сеансы
    FOR sessions IN
        SELECT s.auth_token 
        FROM sessions s 
            JOIN users u ON u.user_id = s.user_id
        WHERE u.username = login.username 
    LOOP
        PERFORM webapi.logout(sessions.auth_token);
    END LOOP;
    -- новый сеанс
    INSERT INTO sessions AS s(auth_token, user_id)
        SELECT gen_random_uuid(), u.user_id
        FROM users u
        WHERE u.username = login.username
    RETURNING s.auth_token
        INTO STRICT auth_token; -- ошибка, если пользователя нет
    RETURN auth_token;
END;
\$\$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;"

###############################################################################
h '2. Функция добавления в корзину'

c 'Во-первых, определим ограничение целостности на таблице cart_items, которое не даст количеству опуститься меньше единицы. Это надежнее и проще, чем реализовывать проверку в коде.'

s 1 "ALTER TABLE public.cart_items ADD CHECK (qty > 0);"

c 'Затем определим функцию add_to_cart. Чтобы не проверять, существует ли книга в корзине, воспользуемся командой INSERT ON CONFLICT.'

s 1 "CREATE OR REPLACE FUNCTION webapi.add_to_cart(
    auth_token uuid,
    book_id bigint,
    qty integer DEFAULT 1
) RETURNS void
AS \$\$
<<local>>
DECLARE
    user_id bigint;
BEGIN
    user_id := check_auth(auth_token);
    IF qty = 1 THEN
        INSERT INTO cart_items(
            user_id, 
            book_id, 
            qty
        ) 
        VALUES (
            user_id,
            book_id,
            1
        )
        ON CONFLICT ON CONSTRAINT cart_items_pkey
            DO UPDATE SET qty = cart_items.qty + 1
        ;
    ELSIF qty = -1 THEN
        UPDATE cart_items ci
        SET qty = ci.qty - 1
        WHERE ci.user_id = local.user_id
            AND ci.book_id = add_to_cart.book_id
        ;
    ELSE
        RAISE EXCEPTION 'qty = %, должно быть 1 или -1', qty;
    END IF;
END;
\$\$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;"

p

c 'При изменении количества книг будут выполняться HOT-обновления, поскольку обновляемое поле (qty) не входит ни в один индекс.'

s 1 "SELECT n_tup_upd, n_tup_hot_upd
FROM pg_stat_all_tables
WHERE relid = 'cart_items'::regclass;"

s 1 "SELECT webapi.login('alice');"
export TOKEN=`sudo -i -u $OSUSER psql -A -t -X -d bookstore2 -c "SELECT auth_token FROM sessions WHERE user_id = 1"`
s 1 "SELECT webapi.add_to_cart(
    auth_token => '$TOKEN',
    book_id => 1
);"
s 1 "SELECT webapi.add_to_cart(
    auth_token => '$TOKEN',
    book_id => 1
);"
s 1 "SELECT webapi.add_to_cart(
    auth_token => '$TOKEN',
    book_id => 1,
    qty => -1
);"

# Чорная магия, чтобы статистика долетела до stats collector
sleep 1
s_bare 1 "SELECT 1;" >/dev/null
sleep 1
s 1 "SELECT n_tup_upd, n_tup_hot_upd
FROM pg_stat_all_tables
WHERE relid = 'cart_items'::regclass;"

###############################################################################

stop_here
cleanup_app
