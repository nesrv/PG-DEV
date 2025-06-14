#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Установка temp_buffers'

s 1 'CREATE DATABASE data_databases;'
s 1 '\c data_databases'

c 'Параметр temp_buffers определяет объем памяти, выделяемый в каждом сеансе под локальный кеш для временных таблиц. Если данные временных таблиц не помещаются в temp_buffers, страницы вытесняются, как это происходит в обычном буферном кеше. Недостаточное значение может привести к деградации производительности при активном использовании временных таблиц.'

c 'Значение по умолчанию для temp_buffers составляет 8 Мбайт:'
s 1 "SELECT name, setting, unit, boot_val, reset_val
FROM pg_settings
WHERE name = 'temp_buffers' \gx"

c 'Установим для всех новых сеансов базы данных значение 32 Мбайта:'

s 1 "ALTER DATABASE data_databases SET temp_buffers = '32MB';"

s 1 '\c'
s 1 'SHOW temp_buffers;'

c 'Настройки, сделанные командой ALTER DATABASE, сохраняются в таблице pg_db_role_setting. Их можно посмотреть в psql следующей командой:'

s 1 '\drds'

c 'Конечно, параметр temp_buffers не обязательно настраивать на уровне базы данных. Например, его можно настроить в postgresql.conf для всего кластера.'

###############################################################################
stop_here
cleanup
demo_end
