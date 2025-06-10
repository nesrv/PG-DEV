#!/bin/bash

. ../lib

init

start_here

###############################################################################
h '1. Кодировки базы данных'

c 'Проверим, что в ОС есть локали с кодировкой koi8:'

s 1 "\! locale -a | grep koi8"

c 'Создаем базы данных с кодировками KOI8R и UTF8:'

s 1 "CREATE DATABASE ${TOPIC_DB}_koi8r
  TEMPLATE template0
  ENCODING 'koi8r'
  LOCALE 'ru_RU.koi8r';"
s 1 "CREATE DATABASE ${TOPIC_DB}_utf8;"

s 1 "\x \l ${TOPIC_DB}_* \x"

c 'Подключаемся к базе с кодировкой KOI8R:'

s 1 "\c ${TOPIC_DB}_koi8r"
s 1 "SET client_encoding = 'UTF8';"

c 'Убедимся, что клиент и сервер используют разные кодировки:'

s 1 "SELECT name, setting
FROM pg_settings
WHERE name LIKE '%encoding';"

c 'Создаем таблицу, содержащую строки с кириллицей:'

s 1 "CREATE TABLE tab AS
  SELECT 'Привет, мир!' AS col;"
s 1 "SELECT * FROM tab;"

psql_close 1

c 'Получаем логическую копию:'

e "pg_dump -d ${TOPIC_DB}_koi8r -Fc -f koi8r.dump"

c 'Содержимое копии выгружается в кодировке базы данных (KOI8R), а в начале файла есть команда установки параметра client_encoding в то же значение KOI8R.'

c "Восстанавливаем таблицу в базе данных ${TOPIC_DB}_utf8:"

e "pg_restore koi8r.dump -d ${TOPIC_DB}_utf8 -t tab"

c 'Благодаря установке client_encoding при восстановлении символы автоматически перекодируются. Проверим, что кириллица корректно перенесена:'

psql_open A 1 -d ${TOPIC_DB}_utf8

s 1 "SELECT * FROM tab;"

###############################################################################
h '2. Номер сегодняшнего дня недели'

c 'Текущие настройки локализации даты и времени:'

s 1 'SHOW lc_time;'

c 'Для получения номера дня недели есть две форматные маски:'
ul 'ID — неделя начинается с понедельника;'
ul 'D  — неделя начинается с воскресенья.'

s 1 "SELECT to_char(current_date, 'TMDay: ID') AS \"ID\",
          to_char(current_date, 'TMDay: D') AS \"D\" ;"


c 'Номер дня недели не зависит от настроек локализации, в частности, от параметра lc_time:'

s 1 "SET lc_time TO 'en_US.utf8';"
s 1 "SELECT to_char(current_date, 'TMDay: ID') AS \"ID\",
          to_char(current_date, 'TMDay: D') AS \"D\" ;"

###############################################################################

stop_here
cleanup
