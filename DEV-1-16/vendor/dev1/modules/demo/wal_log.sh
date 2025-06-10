#!/bin/bash

. ../lib

init

s 1 "CHECKPOINT;" # чтобы не выполнилась неожиданно

start_here 6

###############################################################################

h 'Логическое устройство журнала'

c 'Список менеджеров ресурсов покажет утилита pg_waldump:'

e "${BINPATH_A}pg_waldump -r list" pgwaldump

c 'LSN выводится как два 32-битных числа в шестнадцатеричной системе через косую черту.'

c 'Текущая позиция в журнале:'
s 1 "SELECT pg_current_wal_insert_lsn();"
export LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

###############################################################################
P 8
h 'Физическое устройство журнала'

c "Все журнальные файлы (сегменты) находятся в каталоге $PGDATA_A/pg_wal/, их также показывает специальная функция:"
s 1 "SELECT * FROM pg_ls_waldir() LIMIT 10;"
c 'Имена файлов составлены из трех чисел. Первое — номер линии времени (используется при восстановлении из архива), а два следующих — старшие разряды LSN.'
c 'Размер файлов можно задать при инициализации кластера, по умолчанию — 16 Мбайт.'

c 'Текущая позиция находится в этом файле:'
s 1 "SELECT pg_walfile_name('$LSN');"

p

c 'При помощи утилиты pg_waldump и появившегося в 15-ой версии PostgreSQL расширения pg_walinspect мы можем исследовать содержимое журналов предзаписи.'

c 'Создадим базу данных и в ней небольшую таблицу:'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE TABLE t(note char(10));"

c 'Получим текущую позицию в журнале, после чего вставим в таблицу строку:'

s 1 "SELECT pg_current_wal_insert_lsn();"
export PREV_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

s 1 "INSERT INTO t VALUES ('FOO');"

c 'Теперь позиция журнала такая:'

s 1 "SELECT pg_current_wal_insert_lsn();"
export TARGET_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'Установим расширение и при помощи функции pg_get_wal_record_info рассмотрим сформированную запись в журнале:'

s 1 'CREATE EXTENSION pg_walinspect;'

s 1 "SELECT resource_manager, record_length, xid, start_lsn, prev_lsn, record_type, description
FROM pg_get_wal_record_info('$TARGET_LSN');"

c 'Функция pg_get_wal_block_info покажет нам блок данных — применяемые изменения — соответствующий этой журнальной записи. В столбце block_data можно различить коды символов добавленной строки:'

s 1 "SELECT * FROM pg_get_wal_block_info('$PREV_LSN', '$TARGET_LSN') \gx"

###############################################################################
P 13
h 'Упреждающая запись'

c 'Мы будем заглядывать в заголовок табличной страницы. Для этого понадобится расширение:'

s 1 "CREATE EXTENSION pageinspect;"

# очистка, чтобы вдруг не пришла
# анализ, иначе в wal будет куча изменений pg_statistic и её индекса
vacuumdb --analyze $TOPIC_DB > /dev/null

c 'Начнем транзакцию.'

s 1 "BEGIN;"

c 'Текущая позиция и текущий сегмент журнала:'

s 1 "SELECT pg_current_wal_insert_lsn(), pg_walfile_name(pg_current_wal_insert_lsn());"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'Изменим строку в таблице:'

s 1 "UPDATE t SET note = note || '...upd';"

c 'Позиция в журнале изменилась:'

s 1 "SELECT pg_current_wal_insert_lsn();"

c 'Этот же номер LSN (или меньший, если в журнал попали дополнительные записи) мы найдем и в заголовке измененной страницы:'

s 1 "SELECT lsn FROM page_header(get_raw_page('t',0));"

c 'Завершим транзакцию.'

s 1 "COMMIT;"

c 'Позиция в журнале снова изменилась:'

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'Размер журнальных записей (в байтах), соответствующих нашей транзакции, можно узнать вычитанием одной позиции из другой:'

s 1 "SELECT '$END_LSN'::pg_lsn - '$START_LSN'::pg_lsn;"

c 'Безусловно, в журнал попадает информация обо всех действиях во всем кластере, но в данном случае мы рассчитываем на то, что в системе ничего не происходит.'

p

c 'Теперь воспользуемся утилитой pg_waldump, чтобы посмотреть содержимое журнала.'
c 'Утилита может работать с диапазоном LSN (как в этом примере), может выбрать записи для определенного отношения и отдельного слоя, а также для отдельной страницы или указанной транзакции. Запускать утилиту мы будем от имени суперпользователя, так как ей требуется доступ к журнальным файлам на диске.'

export SEGMENTS=$(s_bare 1 "SELECT pg_walfile_name('$START_LSN')||' '||pg_walfile_name('$END_LSN');")
e "sudo ${BINPATH_A}pg_waldump -p $PGDATA_A/pg_wal -s $START_LSN -e $END_LSN $SEGMENTS" pgwaldump

c 'Мы видим заголовки журнальных записей:'
ul 'операция HOT_UPDATE, относящаяся к странице, которую мы смотрели (rel+blk),'
ul 'операция COMMIT с указанием времени.'

c 'Подобную и даже более подробную информацию мы можем получить, используя функцию из расширения pg_walinspect:'

s 1 "SELECT resource_manager, record_length, xid, start_lsn, prev_lsn, record_type, description
FROM pg_get_wal_records_info('$START_LSN', '$END_LSN') \gx"

c 'Однако использовать инструментарий pg_walinspect получится только при возможности подключения к экземпляру сервера и наличии разрешений на доступ (по умолчанию использовать функции этого расширения разрешено только суперпользователям и ролям, включённым в роль pg_read_server_files).'


###############################################################################

stop_here
cleanup
demo_end
