#!/bin/bash

. ../lib

init

sudo systemctl start slowfs

start_here 12

###############################################################################
h 'Мониторинг ожиданий'

c 'Текущие ожидания можно посмотреть в представлении pg_stat_activity, которое показывает информацию о работающих процессах. Выберем только часть полей:'

s 1 'SELECT pid, backend_type, wait_event_type, wait_event
FROM pg_stat_activity;'

c 'Пустые значения говорят о том, что процесс ничего не ждет и выполняет полезную работу.'

p

c 'Чтобы получить более или менее полную картину ожиданий процесса, требуется выполнять семплирование с некоторой частотой. Воспользуемся расширением pg_wait_sampling.'
c 'Расширение уже установлено из пакета в ОС виртуальной машины курса, но необходимо внести в конфигурационный параметр shared_preload_libraries название загружаемой библиотеки расширения.'\
' Применение этого параметра требует перезагрузки сервера.'

s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pg_wait_sampling';"
pgctl_restart A
psql_open A 1

c 'Теперь создадим расширение в базе данных.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE EXTENSION pg_wait_sampling;"

c 'Расширение позволяет просмотреть некоторую историю ожиданий, которая хранится в кольцевом буфере. Но интереснее увидеть профиль ожиданий — накопленную статистику за все время работы.'
c 'Подождем несколько секунд и заглянем в профиль...'
sleep 3

s 1 "SELECT * FROM pg_wait_sampling_profile ORDER BY 1;"

c 'Поскольку за прошедшее после запуска сервера время ничего не происходило, основные ожидания относятся к типу Activity (служебные процессы ждут, пока появится работа) и Client (psql ждет, пока пользователь пришлет запрос).'
c 'Строки с пустыми значениями event_type и event фиксируют ситуации, когда процесс ничего не ожидает (но работает и занимает процессорное время). За отображение таких строк отвечает параметр pg_wait_sampling.sample_cpu:'

s 1 "SHOW pg_wait_sampling.sample_cpu;"

c 'С установками по умолчанию частота семплирования — 100 раз в секунду. Поэтому, чтобы оценить длительность ожиданий в секундах, значение count надо делить на 100.'

p

c 'Чтобы понять, к какому процессу относятся ожидания, добавим к запросу представление pg_stat_activity:'

s 1 "SELECT p.pid, a.backend_type, a.application_name AS app, p.event_type, p.event, p.count
FROM pg_wait_sampling_profile p
  LEFT JOIN pg_stat_activity a ON p.pid = a.pid
ORDER BY p.pid, p.count DESC;"

c 'Готовимся дать нагрузку с помощью pgbench и наблюдать, как изменится картина.'

e "pgbench -i $TOPIC_DB"

c 'Сбрасываем собранный профиль в ноль и запускаем тест на 30 секунд в отдельном процессе. Одновременно будем смотреть, как изменяется профиль.'

s 1 "SELECT pg_wait_sampling_reset_profile();"

eu_runbg $OSUSER "pgbench -T 30 $TOPIC_DB"

sleep 2

si 1 "SELECT p.pid, a.backend_type, a.application_name AS app, p.event_type, p.event, p.count
FROM pg_wait_sampling_profile p
  LEFT JOIN pg_stat_activity a ON p.pid = a.pid
WHERE a.application_name = 'pgbench'
ORDER BY p.pid, p.count DESC;"

sleep 12

si 1 "\g"

sleep 12

si 1 "\g"

c 'Ожидания процесса pgbench будут получаться разными в зависимости от конкретной системы. В нашем случае с большой вероятностью будет представлено ожидание записи и синхронизации журнала (IO/WALSync, IO/WALWrite).'

wait $BGPID
e_readbg

p

###############################################################################
h 'Легкие блокировки'

c 'Всегда нужно помнить, что отсутствие какого-либо ожидания при семплировании не говорит о том, что ожидания не было. Если оно было короче, чем период семплирования (сотая часть секунды в нашем примере), то могло просто не попасть в выборку.'
c 'Поэтому легкие блокировки скорее всего не появились в профиле — но появятся, если собирать данные в течении длительного времени.'
c 'Чтобы гарантированно увидеть их, подключимся к кластеру slow с замедленной файловой системой: в ней любая операция ввода-вывода будет занимать 1/10 секунды.'

# отображение PGDATA кластера slow на PGDATA кластера main с замедлением
pgctl_stop A
pgctl_start S

c 'Еще раз сбросим профиль и дадим нагрузку.'

s 1 "\c"
s 1 "SELECT pg_wait_sampling_reset_profile();"

eu_runbg $OSUSER "pgbench -T 30 $TOPIC_DB"

sleep 2
si 1 "SELECT p.pid, a.backend_type, a.application_name AS app, p.event_type, p.event, p.count
FROM pg_wait_sampling_profile p
  LEFT JOIN pg_stat_activity a ON p.pid = a.pid
WHERE a.application_name = 'pgbench'
ORDER BY p.pid, p.count DESC;"

sleep 12
si 1 "\g"

sleep 12
si 1 "\g"

c 'Теперь основное ожидание процесса pgbench связано с вводом-выводом, точнее с записью журнала, которая выполняется в синхронном режиме при каждой фиксации. Поскольку (вспомним слайд презентации) запись журнала на диск защищена легкой блокировкой WALWriteLock, она также присутствует в профиле.'

wait $BGPID
e_readbg

###############################################################################

stop_here

sudo systemctl stop slowfs

cleanup
demo_end
