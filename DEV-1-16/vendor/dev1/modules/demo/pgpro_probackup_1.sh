#!/bin/bash

. ../lib
init

start_here 11

###############################################################################
h 'Подготовка pg_probackup'

c 'Чтобы не вводить в командной строке полный путь к pg_probackup, мы использовали символьную ссылку:'
e 'type pg_probackup; ls -l $(which pg_probackup)'

c "При локальной работе пользователь, запускающий pg_probackup, должен также иметь доступ на чтение файлов каталога данных копируемого экземпляра. Для этого достаточно:"
ul "при инициализации кластера запустить утилиту initdb с ключом -g;"
ul "дать группе postgres право чтения каталога PGDATA;"
ul "включить пользователя в группу postgres."
c "Все эти действия были выполнены при настройке виртуальной машины курса."
p

c 'Работа с pg_probackup начинается с создания и инициализации каталога резервных копий.'
e 'sudo mkdir /var/probackup'

c 'Утилите pg_probackup необходим доступ в этот каталог. Мы будем запускать утилиту от имени пользователя student, поэтому сделаем его владельцем каталога.'
e 'sudo chown student:student /var/probackup'

c 'Для инициализации каталога резервных копий используется команда init утилиты pg_probackup, опция -B указывает местоположение каталога:'
e "pg_probackup init -B /var/probackup"

c 'Заглянем в каталог, чтобы проверить результаты инициализации.'
e 'tree --noreport /var/probackup'

c 'При инициализации были созданы два подкаталога:'
ul 'backups — для резервных копий,'
ul 'wal — для архива журнала предзаписи.'
p

c 'Утилита pg_probackup имеет встроенную систему помощи. Получить информацию об отдельных командах утилиты можно командой help:'
e_fake "pg_probackup help init"

c 'Или так:'
e "pg_probackup init --help"
p

c 'Следующий шаг — добавление копируемого экземпляра в каталог копий — выполняется командой add-instance:'
ul 'ключ -D указывает путь к каталогу данных копируемого экземпляра (PGDATA);'
ul 'ключ --instance задает имя экземпляра в каталоге копий.'

e "pg_probackup add-instance -B /var/probackup -D /var/lib/pgpro/ent-16 --instance ent-16"

c 'Снова проверим содержимое каталога копий.'

e 'tree --noreport /var/probackup'

c 'В результате:'
ul 'в каталогах backups и wal появились подкаталоги с именем экземпляра;'
ul 'для экземпляра создан файл конфигурации pg_probackup.conf.'

c 'Содержимое файла конфигурации можно посмотреть средствами ОС, а полную инофрмацию о конфигурации покажет команда show-config утилиты pg_probackup:'

e "pg_probackup show-config -B /var/probackup --instance ent-16" conf

c 'Утилита сохранила в параметре system-identifier уникальный идентификатор экземпляра. Перед выполнением резервного копирования сохраненный идентификатор сверяется с идетификатором резервируемого экземпляра, при несовпадении резервирование не выполняется. Это защищает копии от ошибочных действий администратора.'

c 'Рекомендуется использовать для резервного копирования непривилегированную роль с атрибутом replication. Создадим такую роль и базу данных, к которой эта роль будет подключаться:'

psql_open A 1
s 1 'CREATE ROLE backup LOGIN REPLICATION;'
s 1 "CREATE DATABASE $TOPIC_DB OWNER backup;"

c 'Для резервного копирования роль backup должна иметь привилегии на выполнение некоторых функций схемы pg_catalog в базе backup, предоставим их.'
s 1 "\c $TOPIC_DB"
s 1 \
'
BEGIN;
GRANT USAGE ON SCHEMA pg_catalog TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_is_in_recovery() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_start(text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_stop(boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_create_restore_point(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_switch_wal() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_last_wal_replay_lsn() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current_snapshot() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_snapshot_xmax(txid_snapshot) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_checkpoint() TO backup;
COMMIT;
'
c 'Утилита pg_probackup использует стандартные параметры подключения к базе данных. А свои параметры для удобства можно записать в файл конфигурации с помощью команды set-config:'

e "pg_probackup set-config -B /var/probackup --instance ent-16 -d $TOPIC_DB -U backup"

c 'Вот что получилось:'

e "pg_probackup show-config -B /var/probackup --instance ent-16 | grep -A2 '# Connection parameters'" conf

P 14
###############################################################################
h 'Полная потоковая резервная копия'

c 'Для потоковой доставки WAL используется протокол репликации. Значения параметров по умолчанию и разрешения в pg_hba.conf позволяют его использовать:'
s 1 "SELECT name, setting
FROM pg_settings
WHERE name IN ('wal_level','max_wal_senders','max_replication_slots');

SELECT type, database, user_name, address, auth_method
FROM pg_hba_file_rules()
WHERE 'replication' = ANY(database);"

c 'Получим автономную резервную копию c потоковой доставкой записей WAL:'
ul 'ключ -b FULL запрашивает полную копию;'
ul 'ключ --stream включает потоковую доставку WAL (по умолчанию используется файловая архивация);'
ul 'ключ --temp-slot создает временный слот репликации, который не даст серверу удалить еще не скопированные сегменты WAL.'

e "pg_probackup backup -b FULL -B /var/probackup --instance ent-16 --stream --temp-slot"

c 'Проверим каталог.'

e "pg_probackup show -B /var/probackup --instance ent-16"

id_full=`pg_probackup show -B /var/probackup --instance ent-16 | awk '$1~/ent-16/{print $3}'`

c 'При выполнении резервного копирования pg_probackup вычисляет и сохраняет контрольные суммы для всех файлов. По умолчанию после копирования и перед восстановлением выполняется проверка целостности копии путем сравнения контрольных сумм.'
c 'Можно проверить целостность копии и вручную с помощью команды validate:'

e "pg_probackup validate -B /var/probackup --instance ent-16 -i ${id_full}"

c 'Команда show показывает информацию о копии по ее идентификатору.'

e "pg_probackup show -B /var/probackup --instance ent-16 -i ${id_full}" conf

c 'Поддерживается также вывод информации о копии в формате JSON.'
c 'Эти данные сохраняются в каталоге резервной копии в файле backup.control, а информация о контрольных суммах — в файле backup_content.control.'


P 17
###############################################################################
h 'Разностное копирование'

c 'Произведем какие-нибудь изменения, например, создадим таблицу:'

s 1 "CREATE TABLE IF NOT EXISTS t1 (msg text);"

c 'И запишем в нее данные:'

s 1 "INSERT INTO t1 VALUES ('Полная копия создана. Сделаем разностную.');"

c 'Получим разностную резервную копию:'

e "pg_probackup backup -B /var/probackup --instance ent-16 -b DELTA --stream"

c 'Что теперь в каталоге копий?'

e "pg_probackup show -B /var/probackup --instance ent-16"

id_delta=`pg_probackup show -B /var/probackup --instance ent-16 | awk '$1~/ent-16/ && $6~/DELTA/{print $3}'`

c 'Обратите внимание, насколько разностная копия меньше полной.'
p

c 'Попробуем восстановить кластер из такой копии. Остановим экземпляр.'

pgctl_stop A

c 'Удаляем содержимое PGDATA.'

e "sudo rm -rf ${PGDATA_A}/*"

c "Восстанавливаемый экземпляр обычно запускается от имени пользователя ОС postgres, а каталог PGDATA принадлежит пользователю postgres и группе postgres. Есть два варианта задания прав на файлы каталога PGDATA:"
ul "700 — полные права только для владельца;"
ul "750 — дополнительно права на чтение и доступ в каталог для членов группы postgres."
c "Обычно восстановление производится от имени суперпользователя ОС root с дальнейшей установкой владельца и прав на PGDATA."

p
c 'Восстанавливаем кластер от имени root:'

e "sudo -E ${BINPATH_A}pg_probackup restore -B /var/probackup --instance ent-16 -i ${id_delta}"

c 'Устанавливаем владельца и группу:'

e "sudo chown -R postgres: ${PGDATA_A}"

c 'Устанавливаем права на чтение для группы, это требуется для потоковой доставки WAL.'

e "sudo chmod -R g+rX ${PGDATA_A}"

e "sudo ls -l ${PGDATA_A}"

c 'Запускаем экземпляр.'
pgctl_start A

psql_open A 1 $TOPIC_DB
wait_sql 1 "select not pg_is_in_recovery();"

s 1 "SELECT * FROM t1;"

c 'Мы восстановили данные с помощью разностной копии.'
p

c 'Удалим полную резервную копию. При этом удалится и дочерняя разностная.'
e "pg_probackup delete -B /var/probackup --instance ent-16 -i ${id_full}"

c 'Что осталось в каталоге?'
e "pg_probackup show -B /var/probackup --instance ent-16"

c 'Все резервные копии удалены.'

###############################################################################
P 19
h 'Копирование изменений с помощью PTRACK'

c 'Подключим библиотеку PTRACK к экземпляру.'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'ptrack';"
#s 1 "ALTER SYSTEM SET client_min_messages TO error;"

c 'Экземпляр необходимо перезагрузить.'

pgctl_restart A

c "Установим расширение в базу $TOPIC_DB."

psql_open A 1 $TOPIC_DB

s 1 "CREATE EXTENSION IF NOT EXISTS ptrack;"

c 'Необходимо задать значение параметра ptrack.map_size, рекомендуется 1/1024 объема кластера Postgres Pro:'

s 1 "ALTER SYSTEM SET ptrack.map_size = '1MB';"

c 'Изменение этого параметра также требует рестарта.'

pgctl_restart A

c 'Снова сделаем полную резервную копию с потоковой доставкой WAL.'

e "pg_probackup backup -b FULL -B /var/probackup --instance ent-16 --stream --temp-slot"

c 'Добавим в таблицу еще одну запись.'

psql_open A 1 $TOPIC_DB

s 1 "INSERT INTO t1 VALUES ('Проверим PTRACK.');"

c 'Теперь выполним инкрементальное резервное копирование в режиме PTRACK.'

e "pg_probackup backup -B /var/probackup --instance ent-16 -b PTRACK --stream"

c 'В каталоге резервных копий появится инкрементальная копия:'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-16"

p

c 'Удалим из каталога копируемый экземпляр.'

e "pg_probackup del-instance -B /var/probackup --instance ent-16"

c 'После удаления экземпляра из каталога также удаляются все его резервные копии.'

###############################################################################

stop_here
cleanup
demo_end
