. ../lib

init

backup_dir=/home/$OSUSER/backup
rm -rf $backup_dir

start_here

###############################################################################
h '1. Консолидация'

c 'На первом (публикующем) сервере установим необходимый уровень журнала:'

s 1 "ALTER SYSTEM SET wal_level = logical;"
pgctl_restart A

c 'Создадим таблицу транзакций:'
psql_open A 1

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE TABLE transactions (
    trx_id     bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    debit_acc  integer NOT NULL,
    credit_acc integer NOT NULL,
    amount     numeric(15,2) NOT NULL
);"

p

c 'Чтобы отличать строки разных серверов, понадобится дополнительный столбец. Например:'

s 1 "ALTER TABLE transactions
    ADD server text NOT NULL DEFAULT current_setting('cluster_name');"

p

c 'Чтобы не допустить конфликта значений первичного ключа, выделим каждому из серверов свое множество значений: первому серверу — нечетные, второму — четные. Имя последовательности, которая используется для генерации уникальных номеров, можно узнать с помощью функции:'

s 1 "SELECT pg_get_serial_sequence('transactions','trx_id');"
s 1 "ALTER SEQUENCE transactions_trx_id_seq
    START WITH 1 INCREMENT BY 2;"

c 'Недостатком такой схемы является то, что при появлении третьего сервера ее придется перестраивать.'

p

c 'Другой возможный вариант — использовать для первичного ключа универсальные уникальные идентификаторы, представленные типом данных uuid. Для этого можно использовать встроенную функцию get_random_uuid или средства из расширений pgcrypto и uuid-ossp:'

s 1 "SELECT gen_random_uuid();"

c 'Однако тип uuid занимает 16 байт (bigint — только 8) и генерация нового значения происходит относительно долго.'

p

c 'Еще один вариант — создать составной первичный ключ:'

s_fake 1 "PRIMARY KEY (trx_id, server)"

c 'В этом случае конфликтов гарантированно не будет, но индекс получится больше.'

c 'Мы используем первый вариант: последовательности, генерирующие разные значения.'

p

c 'Теперь развернем второй сервер из резервной копии, как показано в демонстрации.'

e_fake "pg_basebackup --pgdata=$backup_dir"
pg_basebackup --pgdata=$backup_dir --checkpoint=fast

pgctl_stop R
e "sudo rm -rf $PGDATA_R"
e "sudo mv $backup_dir $PGDATA_R"
e "sudo chown -R postgres: $PGDATA_R"
pgctl_start R

psql_open R 2 -d $TOPIC_DB

c 'Заполним таблицу транзакций тестовыми данными — разными на разных серверах.'

s 1 "INSERT INTO transactions(debit_acc, credit_acc, amount)
    SELECT trunc(random()*3),     -- 0..2
           trunc(random()*3) + 3, -- 3..5
           random()*100_000
    FROM generate_series(1,10_000);"

s 1 "SELECT * FROM transactions LIMIT 5;"

c 'На втором сервере не забудем заменить настройки последовательности:'

s 2 "ALTER SEQUENCE transactions_trx_id_seq
    START WITH 2 INCREMENT BY 2 RESTART;"

s 2 "INSERT INTO transactions(debit_acc, credit_acc, amount)
    SELECT trunc(random()*3) + 3, -- 3..5
           trunc(random()*3),     -- 0..2
           random()*100_000
    FROM generate_series(1,10_000);"

s 2 "SELECT * FROM transactions LIMIT 5;"

p

c 'Настроим репликацию с первого сервера на второй.'

s 1 'CREATE PUBLICATION trx_pub FOR TABLE transactions;'

s 2 "CREATE SUBSCRIPTION trx_sub
CONNECTION 'dbname=$TOPIC_DB'
PUBLICATION trx_pub;"

c 'После небольшой паузы убедимся, что данные первого сервера успешно реплицированы:'

wait_sql 2 "SELECT count(*)=20_000 FROM transactions;"

s 2 "SELECT server, count(*) FROM transactions GROUP BY server;"

p

###############################################################################
h '2. Двунаправленная репликация'

c 'Настройка уровня журнала уже скопирована на второй сервер:'
s 2 "SHOW wal_level;"

c 'Теперь очистим таблицы и сбросим последовательности'
s 1 "TRUNCATE TABLE transactions;"
s 1 "SELECT setval('transactions_trx_id_seq',1);"
s 2 "TRUNCATE TABLE transactions;"
s 2 "SELECT setval('transactions_trx_id_seq',2);"

c 'Чтобы публикация не отправляла подписке реплицированные изменения, нужно задать для подписки параметр origin:'
s 2 "ALTER SUBSCRIPTION trx_sub SET (origin = none);"

c ' Теперь настроим репликацию со второго сервера на первый.'
s 2 'CREATE PUBLICATION trx_pub FOR TABLE transactions;'
s 1 "CREATE SUBSCRIPTION trx_sub
CONNECTION 'port=5433 dbname=$TOPIC_DB'
PUBLICATION trx_pub
WITH (origin = none, copy_data = false);"

c 'Проверим:'

s 1 "INSERT INTO transactions(debit_acc, credit_acc, amount)
    SELECT trunc(random()*3),     -- 0..2
           trunc(random()*3) + 3, -- 3..5
           random()*100_000
    FROM generate_series(1,5000);"

s 2 "INSERT INTO transactions(debit_acc, credit_acc, amount)
    SELECT trunc(random()*3) + 3, -- 3..5
           trunc(random()*3),     -- 0..2
           random()*100_000
    FROM generate_series(1,5000);"

wait_sql 1 "SELECT count(*)=10_000 FROM transactions;"
s 1 "SELECT server, count(*) FROM transactions GROUP BY server;"

wait_sql 2 "SELECT count(*)=10_000 FROM transactions;"
s 2 "SELECT server, count(*) FROM transactions GROUP BY server;"

c 'Удалим треть строк на каждом сервере:'

s 1 "DELETE FROM transactions WHERE trx_id % 3 = 1;"
s 2 "DELETE FROM transactions WHERE trx_id % 3 = 2;"

wait_sql 1 "SELECT count(*)=3334 FROM transactions;"
s 1 "SELECT server, count(*) FROM transactions GROUP BY server;"

wait_sql 2 "SELECT count(*)=3334 FROM transactions;"
s 2 "SELECT server, count(*) FROM transactions GROUP BY server;"

c 'Репликация работает.'

p

c 'Удалим подписки, чтобы не оставлять активные слоты репликации.'
s 1 "DROP SUBSCRIPTION trx_sub;"
s 2 "DROP SUBSCRIPTION trx_sub;"

###############################################################################

stop_here
cleanup
