#!/bin/bash

. ../lib

init 19

backup_dir=/home/$OSUSER/backup
rm -rf $backup_dir

start_here
###############################################################################
h '1. Развертывание второго магазина'

c 'Для развертывания сервера выполняем те же команды, что и в демонстрации:'

e "pg_basebackup --pgdata=$backup_dir --checkpoint=fast"

pgctl_stop R
e "sudo rm -rf $PGDATA_R"
e "sudo mv $backup_dir $PGDATA_R"
e "sudo chown -R postgres: $PGDATA_R"
pgctl_start R

s 1 "ALTER SYSTEM SET wal_level = logical;"
psql_close 1
pgctl_restart A

psql_open A 1 -d bookstore2
psql_open R 2 -d bookstore2

c 'Очистим таблицу операций, поскольку второй магазин ведет свою деятельность независимо от основного:'

s 2 "TRUNCATE TABLE operations;"

c 'При выполнении команды TRUNCATE не сработает триггер update_onhand_qty_trigger, поэтому очистим наличное количество вручную:'

s 2 "SELECT book_id, onhand_qty FROM books LIMIT 5;"
s 2 "UPDATE books SET onhand_qty = 0;"

###############################################################################
h '2. Репликация справочников книг и авторов'

c 'Все три связанные таблицы должны входить в публикацию. Иначе на второй сервер реплицируются данные с нарушением внешних ключей:'

# стартуем фоновый процесс
s_bare 1 "SELECT pg_background_detach(pg_background_launch('CALL process_tasks()'));"

s 1 'CREATE PUBLICATION books_pub FOR TABLE books, authors, authorships;'

c 'Как только мы настроим репликацию справочников, на второй сервер в том числе будут передаваться и изменения наличного количества (books.onhand_qty). Очевидно, что это неудачное решение: такие изменения не нужны второму серверу, наличное количество вычисляется на нем независимо от основного сервера.'

c 'Следовало бы поместить наличное количество в отдельную таблицу, изменив соответствующим образом триггер update_onhand_qty_trigger и интерфейсную функцию get_catalog.'

c 'Другой способ — отменять нежелательные обновления с помощью триггера. Он не требует изменения остального кода системы, но не устраняет бесполезную пересылку данных по сети.'

s 2 "CREATE FUNCTION public.keep_onhand_qty() RETURNS trigger
AS \$\$
BEGIN
    NEW.onhand_qty := OLD.onhand_qty;
    RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;"

s 2 "CREATE TRIGGER keep_onhand_qty_trigger
BEFORE UPDATE ON public.books
FOR EACH ROW
WHEN (NEW.onhand_qty IS DISTINCT FROM OLD.onhand_qty)
EXECUTE FUNCTION public.keep_onhand_qty();"

c 'Созданный триггер будет срабатывать только при репликации и не будет мешать обновлять наличное количество при нормальной работе:'

s 2 "ALTER TABLE books ENABLE REPLICA TRIGGER keep_onhand_qty_trigger;"

c 'Создаем подписку. Поскольку текущее состояние справочников уже попало на второй сервер из резервной копии, отключаем начальную синхронизацию данных:'

s 2 "CREATE SUBSCRIPTION books_sub
CONNECTION 'host=localhost port=5432 user=postgres password=postgres dbname=bookstore2'
PUBLICATION books_pub WITH (copy_data = false);"

###############################################################################
stop_here
cleanup_app
