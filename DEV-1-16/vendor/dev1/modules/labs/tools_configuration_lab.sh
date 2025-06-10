#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Параметры, изменение которых требует перезапуска сервера'

s 1 "SELECT name, setting, unit FROM pg_settings WHERE context = 'postmaster';"

###############################################################################
h '2. Установка параметра max_connections'

c 'Текущее значение параметра max_connections:'
s 1 '\dconfig max_conn*'

c 'Допустим, мы решили уменьшить это значение до 50, но ошиблись и вместо нуля написали букву O:'
e "echo max_connections=5O | sudo tee $CONF_A/conf.d/max_connections.conf" conf

c 'Обнаружить ошибку можно, посмотрев в представление pg_file_settings:'
s 1 "SELECT * FROM pg_file_settings WHERE name = 'max_connections'\gx"

c 'Предположим, мы не посмотрели в pg_file_settings и все-таки решили перезапустить сервер:'
psql_close 1
pgctl_restart A

c 'Сервер не запускается. Причина записана в журнал сообщений сервера. Вот последние строки журнала:'
e "tail -n 5 /var/log/postgresql/postgresql-$VERSION_A-main.log"

c 'Исправим ошибку в файле конфигурации:'
e "echo max_connections=50 | sudo tee $CONF_A/conf.d/max_connections.conf" conf

c 'Сервер не работает, поэтому для проверки воспользуемся командой операционной системы.'
e "cat $CONF_A/conf.d/max_connections.conf" conf

c 'Пробуем запустить сервер:'
pgctl_start A

c 'Сервер успешно стартовал, проверяем значение max_connections:'

psql_open A 1
s 1 "SHOW max_connections;"

###############################################################################
stop_here
cleanup
demo_end
