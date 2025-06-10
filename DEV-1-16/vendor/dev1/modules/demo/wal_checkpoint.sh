#!/bin/bash

. ../lib

init

start_here 9

###############################################################################

h 'Контрольная точка'

c "Заглянем в управляющий файл $PGDATA_A/global/pg_control. Это можно сделать с помощью утилиты pg_controldata."

e "sudo ${BINPATH_A}pg_controldata -D $PGDATA_A"

c 'Видим много справочной информации, из которой особый интерес представляют данные о последней контрольной точке и статус кластера: «in production».'

p

c 'Выполним вручную контрольную точку и посмотрим, как это отражается в журнале и в управляющем файле.'

s 1 "SELECT pg_current_wal_insert_lsn();"
export START_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")
s 1 "SELECT pg_walfile_name('$START_LSN');"

s 1 "CHECKPOINT;"

s 1 "SELECT pg_current_wal_insert_lsn();"
export END_LSN=$(s_bare 1 "SELECT pg_current_wal_insert_lsn();")

c 'В журнал попадает запись о том, что контрольная точка пройдена (CHECKPOINT_ONLINE):'

export SEGMENTS=$(s_bare 1 "SELECT pg_walfile_name('$START_LSN')||' '||pg_walfile_name('$END_LSN');")
e "sudo ${BINPATH_A}pg_waldump -p $PGDATA_A/pg_wal -s $START_LSN -e $END_LSN $SEGMENTS" pgwaldump

c 'В описании записи указан LSN начала контрольной точки (redo).'

c 'Сравним с данными управляющего файла:'

e "sudo ${BINPATH_A}pg_controldata -D $PGDATA_A | egrep 'Latest.*location'"

c 'Информация об LSN, очевидно, совпадает.'

###############################################################################
P 11
h 'Восстановление'

c 'Теперь сымитируем сбой, принудительно выключив сервер.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE TABLE test(t text);"
s 1 "INSERT INTO test VALUES ('Перед сбоем');"

kill_postgres A

c 'Сейчас на диске находятся журнальные записи, но табличные страницы не были сброшены на диск.'
c 'Проверим состояние кластера:'

e "sudo ${BINPATH_A}pg_controldata -D $PGDATA_A | grep state"

c 'Состояние не изменилось. При запуске PostgreSQL поймет, что произошел сбой и требуется восстановление.'

pgctl_start A

e "tail -n 6 $LOG_A"

psql_open A 1 $TOPIC_DB
s 1 "SELECT * FROM test;"

c 'Как видим, таблица и данные восстановлены.'

c 'Теперь остановим экземпляр корректно. При такой остановке PostgreSQL выполняет контрольную точку, чтобы сбросить на диск все данные.'

psql_close 1
pgctl_stop A

c 'Проверим состояние кластера:'

e "sudo ${BINPATH_A}pg_controldata -D $PGDATA_A | grep state"

c 'Теперь состояние — «shut down», что соответствует корректной остановке.'

###############################################################################
P 14
h 'Объем журнала'

c 'Снова запустим экземпляр.'

pgctl_start A

c 'Установим минимальное значение min_wal_size и отключим переиспользование, чтобы после контрольной точки оставалось не больше двух сегментов.'

psql_open A 1 $TOPIC_DB
s 1 "ALTER SYSTEM SET min_wal_size = '32MB';"
s 1 "ALTER SYSTEM SET wal_recycle = off;"
s 1 "SELECT pg_reload_conf();"

c 'Добавим строки в таблицу.'

psql_open A 1 $TOPIC_DB
s 1 "INSERT INTO test SELECT g.id::text FROM generate_series(1, 1e6) AS g(id);"
#s 1 "select 'create table test'||n||'(id int primary key generated always as identity)' from generate_series(1,500) s(n)\gexec"

# Чтобы в журнал во время контрольной точки не писалось очень много всего.
#s_bare 1 "EXPLAIN (ANALYZE) SELECT * FROM test;" > /dev/null
#s_bare 1 "VACUUM ANALYZE;" > /dev/null

c 'Список файлов журнала:'
s 1 "SELECT * FROM pg_ls_waldir() ORDER BY modification;"

c 'Выполним вручную контрольную точку и опять посмотрим на журнал:'
s 1 "CHECKPOINT;"

si 1 "SELECT * FROM pg_ls_waldir() ORDER BY modification;"

c 'После контрольной точки в журнале осталось не более двух сегментов, в том числе тот, который был текущим в момент ее начала. А если в кластере после начала контрольной точки происходили какие-либо изменения, в журнале могли появиться и другие сегменты.'

###############################################################################
P 19
h 'Мониторинг'

c 'Параметр checkpoint_warning выводит предупреждение, если контрольные точки, вызванные переполнением размера журнальных файлов, выполняются слишком часто. Его значение по умолчанию:'

s 1 "SHOW checkpoint_warning;"

c 'Его следует привести в соответствие со значением checkpoint_timeout.'

p

c 'Параметр log_checkpoints позволяет получать в журнале сообщений сервера информацию о выполняемых контрольных точках. По умолчанию теперь (начиная с PostgreSQL-15) параметр включен:'

s 1 "SHOW log_checkpoints;"

c 'Запишем что-нибудь в таблицу и выполним контрольную точку.'

s 1 "INSERT INTO test SELECT g.id::text FROM generate_series(1,100000) AS g(id);"

s 1 "CHECKPOINT;"

c 'Вот какую информацию можно будет узнать из журнала сообщений:'

e "tail -n 2 $LOG_A"

c 'Статистика работы процессов контрольной точки и фоновой записи отражается в одном общем представлении (раньше обе задачи решались одним процессом; затем их функции разделили, но представление осталось).'

s 1 "SELECT * FROM pg_stat_bgwriter \gx"

ul 'checkpoints_timed     — контрольные точки по расписанию (checkpoint_timeout);'
ul 'checkpoints_req       — контрольные точки по требованию (max_wal_size) и выполненные вручную;'
#c '* checkpoint_write_time — общее время записи на диск, мс;'
#c '* checkpoint_sync_time  — общее время синхронизации с диском, мс;'
ul 'buffers_checkpoint    — страницы, сброшенные при контрольных точках;'
ul 'buffers_backend       — страницы, сброшенные обслуживающими процессами;'
ul 'buffers_clean         — страницы, сброшенные процессом фоновой записи.'
#c '* maxwritten_clean      — количество остановок по достижению bgwriter_lru_maxpages.'

c 'В хорошо настроенной системе значение buffers_backend должно быть существенно меньше, чем сумма buffers_checkpoint и buffers_clean.'
c 'Большое значение checkpoints_req (по сравнению с checkpoints_timed) говорит о том, что контрольные точки происходят чаще, чем предполагалось.'

p

c 'Однако информация, выдаваемая представлением pg_stat_bgwriter, не вполне корректна: в столбце buffers_backend отражены результаты работы не только клиентских процессов, но и некоторых других'\
' (например, автоочистки). В этот же столбец добавляются операции расширения файлов отношений, хотя это не запись из буферного кеша на диск.'

c 'Уже использованное нами ранее представление pg_stat_io может предоставить данные в более информативном виде:'

s 1 "SELECT backend_type, sum(writes) AS writes, sum(fsyncs) AS fsyncs, sum(extends) AS extends
FROM pg_stat_io WHERE backend_type IN ('checkpointer', 'client backend', 'background writer')
GROUP BY backend_type;"

ul 'writes   — количество операций записи;'
ul 'fsyncs   — количество вызовов fsync;'
ul 'extends  — количество операций расширения отношений.'

###############################################################################

stop_here
cleanup
demo_end
