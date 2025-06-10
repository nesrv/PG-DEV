#!/bin/bash

. ../lib

init_app
roll_to 20

rm -f $H/bookstore.custom
# HOME for OSUSER
export H=`cat /etc/passwd | awk -F ':' '/^'$OSUSER':/ {print $6}'`

start_here

###############################################################################
h '1. Восстановление потерянных данных'

c 'Включим пользователя employee в предопределенную роль pg_read_all_data и от его лица выполним создание резервной копии:'

s 1 'GRANT pg_read_all_data TO employee;'

e "pg_dump --format=custom 'host=localhost user=employee dbname=bookstore password=employee' > $H/bookstore.custom"

c 'Удаляем строки:'

s 1 "DELETE FROM authorship;"

c 'Выполнить восстановление у employee не получится — у него нет прав записи в таблицу, поэтому это делает student:'

e "pg_restore -t authorship --data-only -d bookstore $H/bookstore.custom"

s 1 "SELECT count(*) FROM authorship;"

###############################################################################

stop_here
cleanup_app
