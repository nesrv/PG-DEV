#!/bin/bash

. ../lib
init
start_here

###############################################################################
h '1. Останов сервера'

e "sudo pg_ctlcluster $VERSION_A main stop"

###############################################################################
h '2. Проверка'

c 'Чтобы узнать, включен ли расчет контрольных сумм страниц, запустим утилиту pg_checksums с ключом --check:'

e "sudo /usr/lib/postgresql/$VERSION_A/bin/pg_checksums --check -D /var/lib/postgresql/$VERSION_A/main"

###############################################################################
h '3. Включение расчета контрольных сумм'

c 'Выполняем pg_checksums с ключом --enable:'

e "sudo /usr/lib/postgresql/$VERSION_A/bin/pg_checksums --enable -D /var/lib/postgresql/$VERSION_A/main"

c 'Расчет контрольных сумм включен.'

###############################################################################
h '4. Запуск сервера'

e "sudo pg_ctlcluster $VERSION_A main start"

###############################################################################
stop_here
cleanup
demo_end
