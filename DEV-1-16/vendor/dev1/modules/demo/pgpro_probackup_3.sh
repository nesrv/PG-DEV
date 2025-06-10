#!/bin/bash

. ../lib
init

start_here 5

###############################################################################
h 'Работа с хранилищем S3'

c 'Определим роль backup для резервного копирования и восстановления.'
psql_open A 1
s 1 "CREATE ROLE backup LOGIN REPLICATION;"

c 'Создадим базу данных, к которой будет подключаться роль backup.'
s 1 "CREATE DATABASE $TOPIC_DB OWNER backup;"

c 'Привилегии для роли backup.'
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

p

c 'В виртуальной машине установлено и настроено программное обеспечение MinIO, реализующее API S3. В MinIO уже создана корзина bkp для хранения каталога копий.'
c 'Запустим сервис MinIO.'
e "sudo systemctl enable --now --quiet minio"

c 'Для хранения в облачном хранилище резервных копий используется корзина — аналог каталога. Удалим корзину, если она осталась от ранее выполненных резервных копирований.'
e "/usr/local/bin/mc --quiet rb --force local/bkp"

c 'Теперь создадим корзину.'
e "/usr/local/bin/mc --quiet mb local/bkp"

c 'С помощью текстового редактора создадим файл конфигурации для подключения к хранилищу S3:'
f ~/s3.config conf << EOF
access-key = minioadmin
secret-key = minioadmin
s3-host = localhost
s3-port = 9000
s3-bucket = bkp
s3-secure = off
EOF

ul 'access_key и secret-key задают имя учетной записи и пароль в хранилище;'
ul 's3-host и s3-port — узел и порт службы S3;'
ul 's3-secure — использовать ли протокол https;'
ul 's3-bucket — имя корзины S3.'

p

c 'Инициализируем каталог копий в хранилище S3. Провайдер указывается в ключе --s3, расположение файла с настройками — в ключе --s3-config-file:'
e "pg_probackup init -B /probackup --s3=minio --s3-config-file=/home/student/s3.config"

c 'Если ключ --s3-config-file опущен, pg_probackup ищет файл конфигурации S3 сначала в /etc/pg_probackup/s3.config, а затем в ~postgres/.pg_probackup/s3.config.'
c 'Также параметры подключения можно задать с помощью переменных окружения.'

c 'Добавим в локальный каталог копий экземпляр БД, работающий на удаленном сервере. Каталог копий в хранилище S3.'
e "pg_probackup add-instance -B /probackup -D /var/lib/pgpro/ent-16 --instance ent-16 --s3=minio --s3-config-file=/home/student/s3.config"

c 'Чтобы сократить командную строку, сохраним параметры удаленного доступа в конфигурации.'
e "pg_probackup set-config -B /probackup --instance ent-16 -d $TOPIC_DB -U backup --s3=minio --s3-config-file=/home/student/s3.config"
c 'Внимание! Ключи  --s3=minio и --s3-config-file=/home/student/s3.config задают подключение к S3, они в конфигурацию не записываются и должны задаваться в командной строке явно.'

c 'В конфигурации появились строки, описывающие подключение к S3:'
e "pg_probackup show-config -B /probackup --instance ent-16 --s3=minio --s3-config-file=/home/student/s3.config" conf

c 'Выполним полное резервное копирование в облако.'
e "pg_probackup backup -B /probackup --instance ent-16 -b FULL --stream --s3=minio --s3-config-file=/home/student/s3.config"

c 'В каталоге теперь имеется полная потоковая копия:'
e "pg_probackup show -B /probackup --instance ent-16 --s3=minio --s3-config-file=/home/student/s3.config"

P 10
###############################################################################
h 'Политика хранения копий.'

c 'Выполним еще одно полное резервное копирование.'
e "pg_probackup backup -B /probackup --instance ent-16 -b FULL --stream --s3=minio --s3-config-file=/home/student/s3.config"

p
c 'Кроме последней, актуальной копии, в каталоге есть еще одна полная копия.'
e "pg_probackup show -B /probackup --s3=minio --s3-config-file=/home/student/s3.config"
c 'Если принята политика хранить единственную полную резервную копию, то потоковая копия является устаревшей.'

c 'Количество хранящихся избыточных копий можно задать непосредственно в командной строке. Выполним удаление, указав, что должна храниться только одна копия.'
e "pg_probackup delete -B /probackup --instance=ent-16 --delete-expired --retention-redundancy=1 --s3=minio --s3-config-file=/home/student/s3.config"

c "Проверим состояние каталога резервных копий."
e "pg_probackup show -B /probackup --s3=minio --s3-config-file=/home/student/s3.config"

c 'Осталась единственная полная резервная копия.'
p

c 'Теперь установим политику удержания единственной полной копии.'
e "pg_probackup set-config -B /probackup --instance ent-16 --retention-redundancy=1 --s3=minio --s3-config-file=/home/student/s3.config"

c 'Сделаем полную копию со сжатием. Укажем, что должны быть удалены устаревшие в соответствии с политикой копии и WAL.'
e "pg_probackup backup -b FULL -B /probackup --instance ent-16 --stream --temp-slot --compress --delete-expired --delete-wal --s3=minio --s3-config-file=/home/student/s3.config"

e "pg_probackup show -B /probackup --s3=minio --s3-config-file=/home/student/s3.config"
c 'Осталась единственная полная резервная копия со сжатием.'

P 14
###############################################################################
h 'Настройка журнала отчета'

c 'Настроим параметры для журнала отчета:'
ul '--log-level-file — уровень сообщений, которые будут выводиться в файл журнала;'
ul '--log-level-console — уровень сообщений, которые будут выводиться на консоль;'
ul '--log-filename — имя файла отчета (по умолчанию в подкаталоге log, расположение можно изменить с помощью --log-directory);'
ul '--log-rotation-size — размер файла, при превышении которого выполняется ротация.'

c 'Каталог для отчетов.'
e "rm -rf /home/student/log; mkdir /home/student/log"

e "pg_probackup set-config -B /probackup --instance ent-16 --log-directory=/home/student/log --log-filename=probackup.log --log-rotation-size=500kB --log-level-file=info --log-level-console=warning --s3=minio --s3-config-file=/home/student/s3.config"

e "pg_probackup show-config -B /probackup --instance ent-16 --s3=minio --s3-config-file=/home/student/s3.config" conf

c 'Выполним резервное копирование с только что заданными настройками журнала отчета.'
e "pg_probackup backup -b FULL -B /probackup --instance ent-16 --stream --temp-slot --compress --delete-expired --delete-wal --s3=minio --s3-config-file=/home/student/s3.config"

c 'Заглянем в каталог с отчетом:'
e "ls -lh /home/student/log"

c 'Еще раз выполним резервное копирование, включив подробный вывод сообщений в отчет.'
e "pg_probackup backup -b FULL -B /probackup --instance ent-16 --stream --temp-slot --compress --delete-expired --delete-wal --log-level-file=verbose --s3=minio --s3-config-file=/home/student/s3.config"

c 'В файл отчета записалось большое количество сообщений.'
e "ls -lh /home/student/log"

c 'Повторим эксперимент с уровнем важности сообщений по умолчанию. Файл журнала отчета достиг размера, при котором должна произойти ротация:'
e "pg_probackup backup -b FULL -B /probackup --instance ent-16 --stream --temp-slot --compress --delete-expired --delete-wal --s3=minio --s3-config-file=/home/student/s3.config"

c 'В результате ротации журнала отчета старые сообщения были стерты и размер файла уменьшился.'
e "ls -lh /home/student/log"

###############################################################################

stop_here
cleanup
demo_end
