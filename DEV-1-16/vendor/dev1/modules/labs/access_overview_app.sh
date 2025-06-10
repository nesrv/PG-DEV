#!/bin/bash

. ../lib

init_app
roll_to 19

start_here

###############################################################################
h '1. Создание ролей'

s 1 "CREATE ROLE employee LOGIN PASSWORD 'employee';"
s 1 "CREATE ROLE buyer LOGIN PASSWORD 'buyer';"

c 'Настройки по умолчанию разрешают подключение с локального адреса по паролю. Нас это устраивает.'

###############################################################################
h '2. Привилегии public'

c 'У роли public надо отозвать лишние привилегии.'

s 1 "REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA bookstore FROM public;"
s 1 "REVOKE CONNECT ON DATABASE bookstore FROM public;"

###############################################################################
h '3. Разграничение доступа'

c 'Функции с правами создавшего.'

s 1 "ALTER FUNCTION get_catalog(text,text,boolean) SECURITY DEFINER;"
s 1 "ALTER FUNCTION update_catalog() SECURITY DEFINER;"
s 1 "ALTER FUNCTION add_author(text,text,text) SECURITY DEFINER;"
s 1 "ALTER FUNCTION add_book(text,integer[]) SECURITY DEFINER;"
s 1 "ALTER FUNCTION buy_book(integer) SECURITY DEFINER;"
s 1 "ALTER FUNCTION book_name(integer,text,integer) SECURITY DEFINER;"
s 1 "ALTER FUNCTION authors(books) SECURITY DEFINER;"

c 'Привилегии покупателя: покупатель должен иметь доступ к поиску книг и их покупке.'

s 1 "GRANT CONNECT ON DATABASE bookstore TO buyer;"
s 1 "GRANT USAGE ON SCHEMA bookstore TO buyer;"

s 1 "GRANT EXECUTE ON FUNCTION get_catalog(text,text,boolean) TO buyer;"
s 1 "GRANT EXECUTE ON FUNCTION buy_book(integer) TO buyer;"

c 'Привилегии сотрудника: сотрудник должен иметь доступ к просмотру и добавлению книг и авторов, а также к каталогу для заказа книг.'

s 1 "GRANT CONNECT ON DATABASE bookstore TO employee;"
s 1 "GRANT USAGE ON SCHEMA bookstore TO employee;"

s 1 "GRANT SELECT,UPDATE(onhand_qty) ON catalog_v TO employee;"
s 1 "GRANT SELECT ON authors_v TO employee;"
s 1 "GRANT SELECT ON operations_v TO employee;"

s 1 "GRANT EXECUTE ON FUNCTION book_name(integer,text,integer) TO employee;" # Используется в catalog_v
s 1 "GRANT EXECUTE ON FUNCTION authors(books) TO employee;" # Используется в catalog_v
s 1 "GRANT EXECUTE ON FUNCTION author_name(text,text,text) TO employee;" # Используется в authors_v
s 1 "GRANT EXECUTE ON FUNCTION add_book(text,integer[]) TO employee;"
s 1 "GRANT EXECUTE ON FUNCTION add_author(text,text,text) TO employee;"

###############################################################################

stop_here
cleanup_app
