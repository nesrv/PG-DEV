#!/bin/bash


. ../lib
init
start_here 11
###############################################################################
h 'Подготовка pg_probackup.'

c 'Работа с pg_probackup начинается с создания и инициализации каталога резервных копий.'

e 'sudo mkdir /var/probackup'

c 'Резервное копирование будет производиться с помощью учетной записи student, поэтому каталог должен принадлежать пользователю student.'

e 'sudo chown student:student /var/probackup'

c 'Для инициализации каталога резервных копий используется режим init команды pg_probackup. Опция -B указывает местоположение каталога. За редким исключением, опция -B будет использоваться с командой pg_probackup в большинстве режимов.'

e "${BINPATH_A}pg_probackup init -B /var/probackup"

c 'Заглянем в каталог - проверим результаты инициализации.'

e 'ls -RF /var/probackup'

c 'В результате инициализации были созданы два подкаталога: backups и wal.'
ul 'В первом будут размещаться резервные копии. '
ul 'Второй используется в режиме архивирования сегментов журнала предзаписи WAL.'

c 'Следует отметить, что pg_probackup имеет развитую встроенную систему помощи. Так, например, для получения помощи по режиму init можно сделать так:'

e "${BINPATH_A}pg_probackup help init"

c 'Или так:'

e "${BINPATH_A}pg_probackup init --help"

c 'Следующий шаг - добавление копируемого экземпляра в каталог копий. Выполняется в режиме add-instance.'
ul 'С помощью опции -D необходимо указать расположение каталога данных копируемого экземпляра (PGDATA).'
ul 'Опция --instance задает имя экземпляра, для которого будут выполняться команды резервного копирования, восстановления и прочие.'

e "${BINPATH_A}pg_probackup add-instance -B /var/probackup -D /var/lib/pgpro/ent-13 --instance ent-13"

c 'Снова проверим содержимое каталога копий.'

e 'ls -RF /var/probackup'

c 'Обратите внимание на два момента:'
ul 'во-первых были созданы индивидуальные подкаталоги, с именами, соответствующими имени экземпляра, заданного опцией --instance.'
ul 'во-вторых появился индивидуальный файл конфигурации резервного копирования экземпляра.'

c 'Конечно, этот файл конфигурации можно исследовать с помощью обычных утилит ОС, например, cat. Но pg_probackup предоставляет специальный режим работы show-config, удобный для просмотра конфигурации.'

e "${BINPATH_A}pg_probackup show-config -B /var/probackup --instance ent-13"

c 'В полученной конфигурации присутствует специальный системный идентификатор (system-identifier), генерирующийся всякий раз при добавлении копируемого экземпляра в каталог копий.'
c 'Наличие сгенерированного идентификатора исключает нарушение целостности резервных копий в каталоге, которое могло бы без этого произойти в результате ошибочных действий администратора.'
c 'Если при выполнении резервного копирования командой pg_probackup выявляется несоответствие системного идентификатора в каталоге резервируемому экземпляру (например, в результате пересоздания кластера данных экземпляра с помощью initdb), резервирование не выполняется. Таким образом, выполненные ранее резервные копии не портятся и из них можно восстановиться.'

c 'Также в конфигурации отмечено, что подключение к экземпляру осуществляется посредством учетной записи student (pgdatabase = student).'

c 'Роль student имеет привилегии суперпользователя. Рекомендуется выполнять операции резервного копирования экземпляров с помощью непривилегированной роли, имеющей атрибут replication.'

psql_open A 1

s 1 'CREATE ROLE backup LOGIN REPLICATION;'

c 'Создадим базу данных, к которой будет подключаться роль backup.'

s 1 'CREATE DATABASE backup OWNER backup;'

c 'Для выполнения резервного копирования роль backup должна обладать минимально необходимыми правами. Подключимся к базе данных backup и предоставим роли backup требуемые права:'

s 1 '\c backup'
s 1 \
'
BEGIN;
GRANT USAGE ON SCHEMA pg_catalog TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_is_in_recovery() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_start_backup(text, boolean, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_stop_backup(boolean, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_create_restore_point(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_switch_wal() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_last_wal_replay_lsn() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current_snapshot() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_snapshot_xmax(txid_snapshot) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_checkpoint() TO backup;
COMMIT;
'

s 1 '\c student'

c 'Утилита pg_probackup использует обычные опции подключения к базе данных. Чтобы сделать командную строку чуть короче опции можно задать в качестве параметров конфигурации резервируемого экземпляра. Это делается с помощью режима set-config.'

e "${BINPATH_A}pg_probackup set-config -B /var/probackup --instance ent-13 -d backup -U backup"

c 'Предыдущая команда внесла параметры подключения от имени роли backup к базе данных backup в конфигурацию резервируемого экземпляра с идентификатором ent-13. Проверим это:'

e "${BINPATH_A}pg_probackup show-config -B /var/probackup --instance ent-13"

P 14
###############################################################################
h 'Полная потоковая резервная копия'

c 'Пока ни одной резервной копии не было создано. Проверим:'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

c 'Потоковый режим требует соответствующей установки параметров wal_level, max_wal_senders и max_replication_slots. Проверим:'

s 1 "SELECT name, setting
FROM pg_settings
WHERE name IN ('wal_level','max_wal_senders','max_replication_slots');"

c 'Получим полную резервную копию в потоковом режиме.'

e "${BINPATH_A}pg_probackup backup -b FULL -B /var/probackup --instance ent-13 --stream --temp-slot"

c 'Опция -b задает разновидность резервного копирования - FULL.'
c 'Опция --stream включает потоковый режим. По умолчанию - режим архивирования WAL.'
c 'Опция --temp-slot создает временный слот репликации для исключения удаления сегментов WAL, еще не попавших в копию.'

c 'Проверим каталог.'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

inst_full=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$1~/ent-13/{print $3}'`

c 'При выполнении резервного копирования pg_probackup вычисляет контрольные суммы для всех файлов.'
c 'По умолчанию после создания резервной копии выполняется проверка целостности копии посредством контрольных сумм.'
c 'Проверка целостности также выполняется непосредственно перед восстановлением для выявления возможных повреждений резервных копий.'
c 'Вручную проверить целостность копии можно с помощью pg_probackup validate:'

e "${BINPATH_A}pg_probackup validate -B /var/probackup --instance ent-13 -i ${inst_full}"

c 'С помощью show можно получить подробную информацию о копии, если указать ее идентификатор.'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13 -i ${inst_full}"

c 'Поддерживается вывод подробной информации о копии в формате JSON.'

###############################################################################
P 17
h 'Разностное копирование.'

c 'Произведем какие-либо изменения, например, создадим таблицу.'

s 1 "CREATE TABLE IF NOT EXISTS t1( msg text );"

c 'И запишем в нее данные:'

s 1 "INSERT INTO t1 VALUES( 'Полная копия создана. Сделаем разностную.' );"

c 'Получим разностную резервную копию:'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b DELTA --stream"

c 'Что теперь в каталоге?'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

inst_delta=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$1~/ent-13/ && $6~/DELTA/{print $3}'`

c 'Обратите внимание, насколько велика разница в размерах полной и разностной резервных копий.'

c 'Проверим, можно ли восстановиться из такой копии. Остановим экземпляр.'

psql_close 1

pgctl_stop A

c 'Удаляем содержимое PGDATA'

eu postgres "rm -rf ${PGDATA_A}/*"

c 'Восстанавливаем с правами root.'

e "sudo ${BINPATH_A}pg_probackup restore -B /var/probackup --instance ent-13 -i ${inst_delta}"

c 'Устанавливаем владельца и группу.'

e "sudo chown -R postgres:postgres ${PGDATA_A}"

c 'Устанавливаем права на чтение для группы. Это требуется для работы в потоковом режиме.'

e "sudo chmod -R g+rX ${PGDATA_A}"

e "sudo ls -l ${PGDATA_A}"

c 'Стартуем.'

pgctl_start A

psql_open A 1
wait_sql 1 "select not pg_is_in_recovery();"


s 1 "SELECT * FROM t1;"

c 'Данные восстановлены. Возможность восстановления с помощью разностных копий проверена.'

c 'Удалим полную резервную копию. При этом должна удалиться и разностная тоже.'

e "sudo ${BINPATH_A}pg_probackup delete -B /var/probackup --instance ent-13 -i ${inst_full}"

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

c 'Все резервные копии удалены.'

###############################################################################
P 19
h 'Копирование изменений с помощью PTRACK.'

c 'Подключим PTRACK к экземпляру.'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'ptrack';"
s 1 "ALTER SYSTEM SET client_min_messages TO error;"

c 'Экземпляр необходимо перезагрузить.'

psql_close 1

pgctl_restart A

psql_open A 1

c 'Подключим расширение. И зададим значение для параметра ptrack.map_size'

s 1 "\c backup"
s 1 "CREATE EXTENSION IF NOT EXISTS ptrack;"
s 1 "\c student"

c 'Рекомендуется задавать ptrack.map_size равным  ( объём кластера Postgres Pro в мегабайтах ) / 1024'

s 1 "ALTER SYSTEM SET ptrack.map_size = '1MB';"

c 'Изменение параметра ptrack.map_size также требует рестарта.'

pgctl_restart A

c 'Снова сделаем полную резервную копию в потоковом режиме.'

e "${BINPATH_A}pg_probackup backup -b FULL -B /var/probackup --instance ent-13 --stream --temp-slot"

psql_open A 1

c 'Добавим в таблицу еще одну запись.'

s 1 "INSERT INTO t1 VALUES( 'Проверим PTRACK.' );"

c 'Выполним инкрементальное резервное копирование в режиме PTRACK.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PTRACK --stream"

c 'В каталоге резервных копий присутствует инкрементальная копия, выполненная в режиме PTRACK:'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

inst_ptrack=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$1~/ent-13/ && $6~/PTRACK/{print $3}'`

c 'Удалим из каталога копируемый экзепляр.'

# e "sudo ${BINPATH_A}pg_probackup del-instance -B /var/probackup --instance ent-13"
e "${BINPATH_A}pg_probackup del-instance -B /var/probackup --instance ent-13"

c 'После удаления из каталога копируемого экземпляра, также удаляются все его резервные копии.'

###############################################################################
P 22
h 'Удаленный режим.'

c 'Удаленный режим основан на сетевом протоколе SSH. Пользователь, выполняющий резервное копирование, и postgres должны обменяться публичными ключами, сгенерированными без парольной фразы. Настройка SSH и обмен публичными ключами в виртуальной машине курса уже автоматически произведен. Никаких дополнительных действий не требуется.'

c 'Добавим в каталог экземпляр БД, работающий на удаленном сервере. Каталог копий на локальном сервере. И удаленный и локальный сервер здесь на localhost.'

e "${BINPATH_A}pg_probackup add-instance -B /var/probackup -D /var/lib/pgpro/ent-13 --instance ent-13 --remote-host=localhost --remote-user=postgres"

c 'Проверим каталог. В нем пока ничего нет.'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

c 'Чтобы не удлинять командную строку опциями удаленного доступа, запишем их в конфигурацию.'

e "${BINPATH_A}pg_probackup set-config -B /var/probackup --instance ent-13 -d backup -U backup --remote-host=localhost --remote-user=postgres"

c 'Проверим конфигурацию.'

e "${BINPATH_A}pg_probackup show-config -B /var/probackup --instance ent-13"

c 'Выполним полное резервное копирование в потоковом режиме с удаленного сервера.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b FULL --stream"

c 'Выведем содержимое каталога резервных копий:'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

inst_full=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$1~/ent-13/ && $6~/FULL/{print $3}'`

###############################################################################
P 25
h 'Режим архивирования WAL.'

c 'Подготовим экземпляр к работе в режиме архивирования WAL.'

s 1 "ALTER SYSTEM SET archive_mode = on;"

s 1 "ALTER SYSTEM SET archive_command = '/opt/pgpro/ent-13/bin/pg_probackup archive-push -B /var/probackup --instance=ent-13 --wal-file-path=%p --wal-file-name=%f --remote-host=localhost --remote-user=student';"

c 'Экземпляр необходимо перезагрузить.'

psql_close 1

pgctl_restart A

psql_open A 1

c 'Проверьте, работает ли архивирование WAL с сохранением в каталог копий.'

e "ls -lR /var/probackup/wal"

s 1 "SELECT pg_switch_wal();"
s 1 "CHECKPOINT;"

e "ls -lR /var/probackup/wal"

c 'Получим информацию об архиве WAL средставми pg_probackup.'

e "${BINPATH_A}pg_probackup show -B /var/probackup --archive"

c 'Выполним полное резервное копирование в режиме архивирования. Опция --stream не нужна.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b FULL"

c 'Проверим каталог резервных копий:'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

inst_full_wal=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$7~/ARCHIVE/ && $6~/FULL/{print $3}'`

c 'Имеется еще один режим инкрементального копирования - PAGE. Он требует WAL. Добавим в таблицу еще одну запись.'

s 1 "INSERT INTO t1 VALUES( 'Проверим режим PAGE.' );"

c 'Выполним инкрементальное резервное копирование в режиме PAGE.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PAGE"

c 'Проверим каталог резервных копий:'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

inst_page=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$1~/ent-13/ && $6~/PAGE/{print $3}'`

c 'Проверим, можно ли восстановиться из этого архива.'

psql_close 1

pgctl_stop A

c 'Удаляем содержимое PGDATA'

eu postgres "rm -rf ${PGDATA_A}/*"

c 'Восстанавливаем. К команде добавим опции для автоматического формирования restore_command.'

e "${BINPATH_A}pg_probackup restore -B /var/probackup --instance ent-13 -i ${inst_page} --archive-host=localhost --archive-user=student"

inst_page=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$1~/ent-13/ && $6~/PAGE/{print $3}'`

c 'Устанавливаем права на чтение для группы.'

e "sudo chmod -R g+rX ${PGDATA_A}"

e "sudo ls -l ${PGDATA_A}"

c 'Стартуем.'

pgctl_start A

psql_open A 1

wait_sql 1 "select not pg_is_in_recovery();"

s 1 "SELECT * FROM t1;"

c 'Проверим пишущую транзакцию.'

s 1 "INSERT INTO t1 VALUES( 'Проверим пишущую транзакцию.' );"

s 1 "SELECT * FROM t1;"

c 'После восстановления в удаленном режиме база данных восстановлена и работоспособна.'

psql_close 1

###############################################################################
P 27
h 'Частичное восстановление.'

c 'Для выполнения частичного восстановления роль backup должна иметь право на чтение pg_catalog.pg_database в базе данных backup.'

psql_open A 1

s 1 '\c backup'

s 1 'GRANT SELECT ON TABLE pg_catalog.pg_database TO backup;'

s 1 '\c student'

c 'Для демонстрации частичного восстановления создадим базу данных, и поместим в нее данные.'

s 1 'CREATE DATABASE fatedb;'

e "psql -d fatedb -c 'CREATE TABLE prof_fate( button text )'"

e "psql -d fatedb -c \"INSERT INTO prof_fate VALUES ('Push the Button, Max!')\""

e "psql -d fatedb -c 'SELECT * FROM prof_fate'"

c 'Выполним инкрементальное копирование. Созданая база должна попасть в резервную копию.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PAGE"

c 'Проверим каталог резервных копий:'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

inst_page=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$8~/^2/ && $6~/PAGE/{print $3}'`

c 'Команда merge объединяет инкрементальные копии с родительской полной копией.'

e "${BINPATH_A}pg_probackup merge -B /var/probackup --instance ent-13 -i ${inst_page}"

c 'Останавливаем экземпляр.'

psql_close 1

pgctl_stop A

c 'Удаляем содержимое PGDATA.'

eu postgres "rm -rf ${PGDATA_A}/*"

c 'По результатам полного восстановления база данных fatedb должна быть на месте.'

e "${BINPATH_A}pg_probackup restore -B /var/probackup --instance ent-13 -i ${inst_page} --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

c 'Стартуем.'

pgctl_start A
psql_open A 1

wait_sql 1 "select not pg_is_in_recovery();"


c 'Получим список баз данных в восстановленном экземпляре. База данных fatedb должна быть на месте.'

e "psql -l"

e "psql -d fatedb -c 'SELECT * FROM prof_fate'"

psql_close 1

c 'Останавливаем экземпляр.'

pgctl_stop A

c 'Снова удаляем содержимое PGDATA.'

eu postgres "rm -rf ${PGDATA_A}/*"

c 'По результатам полного восстановления база данных fatedb должна быть на месте.'

c 'Частично восстановим данные кластера. Не будем восстанавливать базу данных fatedb.'

e "${BINPATH_A}pg_probackup restore -B /var/probackup --instance ent-13 -i ${inst_page} --db-exclude=fatedb --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

c 'Стартуем.'

pgctl_start A
psql_open A 1

wait_sql 1 "select not pg_is_in_recovery();"


c 'База данных fatedb должна быть в списке. Но pg_probackup НЕ копирует данные, база пустая.'
e "psql -l"

c 'Запрос не должен завершиться успехом. Так как частичное восстановление не поместило данные fatedb на место.'
e "psql -d fatedb -c 'SELECT * FROM prof_fate'"

psql_close 1

###############################################################################
P 29
h 'Инкрементальное восстановление.'

c 'Инкрементальное восстановление включается опцией -I с указанием режима:'
ul 'CHECKSUM из копии восстанавливаются только те страницы в PGDATA экземпляра, имеющие некорректную контрольную сумму;'
ul 'LSN - восстановление с учетом точки расхождения данных в PGDATA по стравнению с резервной копией;'
ul 'NONE — обычное восстановление без инкрементальных оптимизаций.'

pgctl_stop A

c 'Инкрементальное восстановление в режиме CHECKSUM.'

e "${BINPATH_A}pg_probackup restore -B /var/probackup --instance ent-13 -i ${inst_page} -I CHECKSUM --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

pgctl_start A

psql_open A 1
wait_sql 1 "select not pg_is_in_recovery();"


c 'База данных fatedb должна быть восстановлена.'
e "psql -l"

c 'Запрос должен завершиться успехом.'
e "psql -d fatedb -c 'SELECT * FROM prof_fate'"

psql_close 1

###############################################################################
P 31
h 'Восстановление к моменту времени в прошлом.'

c 'Пока в каталоге лишь две полные копии.'
e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

full_arch_lsn=`/opt/pgpro/ent-13/bin/pg_probackup show -B /var/probackup --instance ent-13 | awk '$7~/ARCHIVE/ && $6~/FULL/{print $14}'`

c 'До выполнения следующего инкрементального резервного копирования.'

psql_open A 1

s 1 "SELECT * FROM t1;"

c 'Добавим еще одну запись и выполним инкрементальное копирование.'

s 1 "INSERT INTO t1 VALUES( 'Запись попадет в инкрементальную копию.' );"

psql_close 1

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PAGE"

c 'Проверим каталог резервных копий:'

e "${BINPATH_A}pg_probackup show -B /var/probackup --instance ent-13"

c 'Используя режим validate можно проверить возможность восстановления к заданной точке.'
c "Идентификатор копии указывать не требуется. Проверим возможность восстановиться к LSN ${full_arch_lsn}"

e "${BINPATH_A}pg_probackup validate -B /var/probackup --instance ent-13 --recovery-target-lsn=${full_arch_lsn}"

c "Выполним восстановление к LSN ${full_arch_lsn}"

pgctl_stop A

c 'Удаляем содержимое PGDATA.'

eu postgres "rm -rf ${PGDATA_A}/*"

e "${BINPATH_A}pg_probackup restore -B /var/probackup --instance ent-13 --recovery-target-lsn=${full_arch_lsn} --remote-user=postgres --remote-host=localhost --archive-host=localhost --archive-user=student"

c 'Стартуем.'

pgctl_start A

psql_open A 1

s 1 "SELECT * FROM t1;"

c 'Сервер в состоянии hot standby.'

s 1 "SELECT pg_is_in_recovery();"

c 'Выполним повышение до мастера.'

s 1 "SELECT pg_promote( true, 20 );"

c "Данные восстановлены к моменту, соответствующему LSN ${full_arch_lsn}"

psql_close 1

c 'Выполним полное копирование в режиме архивирования WAL, так как текущий экземпляр восстановлен к точке времени в прошлом.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b FULL"

###############################################################################
P 37
h 'Политики хранения.'

c 'Кроме последней, актуальной копии, в каталоге есть еще полные копии.'

e "${BINPATH_A}pg_probackup show -B /var/probackup"

c 'Если принята политика хранить единственную полную резервную копию, то потоковая копия является устаревшей.'
c 'Политику хранения не обязательно устанавливать с помощью set-config.'
c 'Количество хранящихся избыточных копий можно задать непосредственно в командной строке.'

c 'Укажем, что должна храниться единственная копия и выполним удаление. Устаревшая копия будет автоматически удалена.'

e "${BINPATH_A}pg_probackup delete -B /var/probackup --instance=ent-13 --delete-expired --retention-redundancy=1"

c "Проверим состояние каталога резервных копий."

e "${BINPATH_A}pg_probackup show -B /var/probackup"

c 'Осталась единственная полная резервная копия.'

c 'Установим политику удержания единственной полной копии.'

e "${BINPATH_A}pg_probackup set-config -B /var/probackup --instance ent-13 --retention-redundancy=1"

c 'Создадим еще одну полную копию. Используем сжатие. Укажем, что должны быть удалены устаревшие в соответствии с политикой копии и WAL.'

e "${BINPATH_A}pg_probackup backup -b FULL -B /var/probackup --instance ent-13 --stream --temp-slot --compress --delete-expired --delete-wal"

e "${BINPATH_A}pg_probackup show -B /var/probackup"

c 'Должна быть единственная полная резервная копия со сжатием.'

## TODO
# Закрепление резервных копий.
# Политики хранения WAL.

###############################################################################
P 39
h 'Настройка журнала отчета.'

c 'Настроим параметры по умолчанию для журнала отчета:'
ul '--log-level-file - уровень сообщений, которые будут выводиться в файл журнала.'
ul '--log-filename - имя файла отчета.'
ul '--log-rotation-size - пороговый размер файла, по превышению выполняется ротация.'

e "${BINPATH_A}pg_probackup set-config -B /var/probackup --instance ent-13 --log-filename=probackup.log --log-rotation-size=400 --log-level-file=info --log-level-console=warning"

c 'Ротация журнала будет производиться, если он превысит по размеру 400КБ.'
c 'Журнал отчета по умолчанию создается в подкаталоге log. Изменить расположение журнала можно с помощью --log-directory.'
c 'Вывод сообщений на консоль производится в поток stderr. Уровень важности сообщений задает --log-level-console.'

e "${BINPATH_A}pg_probackup show-config -B /var/probackup --instance ent-13"

c 'Выполним резервное копирование с только что выполненными настройками журнала отчета.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PTRACK"

c 'Заглянем в каталог с отчетом.'
e "ls -lh /var/probackup/log"

c 'Снова выполним резервное копирование, но включим режим максимальной подробности вывода сообщений в журнал отчета.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PTRACK --log-level-file=verbose"

c 'В файл журнала отчета записалось порядка 400КБ сообщений.'
e "ls -lh /var/probackup/log"

c 'Повторим эксперимент с уровнем важности сообщений по умолчанию. Файл журнала отчета уже достиг размера, когда должна быть выполнена ротация.'

e "${BINPATH_A}pg_probackup backup -B /var/probackup --instance ent-13 -b PTRACK"

c 'В результате ротации журнала отчета старые сообщения стерты и размер файла уменьшился.'
e "ls -lh /var/probackup/log"

###############################################################################
stop_here
cleanup
demo_end
