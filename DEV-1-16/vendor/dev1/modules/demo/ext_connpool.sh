#!/bin/bash

. ../lib

init

if [ -f /etc/pgbouncer/pgbouncer.ini.save ]
then
	sudo cp /etc/pgbouncer/pgbouncer.ini.save /etc/pgbouncer/pgbouncer.ini
fi
sudo cp /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini.save

sudo service pgbouncer restart  # на случай, если "залипнет" PAUSE

start_here 11

###############################################################################
h 'Минимальная настройка'

c 'Файл настроек PgBouncer:'

e 'sudo ls -l /etc/pgbouncer/pgbouncer.ini'

e "sudo grep '^[^;]' /etc/pgbouncer/pgbouncer.ini" ini

ul 'Секция [databases] позволяет переадресовывать обращения к разным БД на разные серверы PostgreSQL (в нашем случае это не используется);'
ul 'PgBouncer слушает порт 6432;'
ul 'Используется аутентификация scram-sha-256;'
ul 'Роль student может выполнять администрирование PgBouncer;'
ul 'Используется режим пула транзакций.'

p

c 'Файл пользователей:'

e 'sudo cat /etc/pgbouncer/userlist.txt'

c 'Чтобы не синхронизировать пароли, можно получать их непосредственно с сервера БД:'

e "sudo grep 'auth_query' /etc/pgbouncer/pgbouncer.ini" ini

p

c 'Попробуем подключиться. Поскольку PgBouncer настроен на парольную scram-sha-256-аутентификацию, зададим пароль явно в строке подключения (можно было бы использовать файл ~/.pgpass):'

psql_open A 1 "postgresql://student@localhost:6432/student?password=student"

s 1 "SELECT pg_backend_pid();"

c 'Подключение работает.'
c 'Теперь закроем соединение и откроем его заново:'

psql_close 1
psql_open A 1 "postgresql://student@localhost:6432/student?password=student"

s 1 "SELECT pg_backend_pid();"

c 'Фактически мы продолжаем работать в том же самом сеансе, который PgBouncer удерживает открытым.'

P 13

###############################################################################
h 'Консоль управления'

c 'Чтобы работать с консолью управления PgBouncer, необходимо подключиться к одноименной базе данных (это могут сделать пользователи, определенные в параметрах admin_users и stat_users).'

psql_open A 1 "postgresql://student@localhost:6432/pgbouncer?password=student"

c 'Теперь мы работаем не с PostgreSQL — команды обрабатывает сам PgBouncer.'
c 'Например, можно получить информацию об используемых пулах:'

s 1 "SHOW POOLS \gx"

c 'Работой пула управляет ряд параметров, которые мы уже видели в конфигурационном файле. Из консоли управления можно увидеть их текущие и умолчательные значения и при необходимости изменить их:'

s 1 "SET max_prepared_statements = 10;"

c 'Вывод команды SHOW CONFIG, показывающий информацию о параметрах, достаточно объемный, поэтому отфильтруем его, чтобы увидеть только один параметр:'
c ''

s_fake 1 $PSQL_PROMPT"SHOW CONFIG \gx"
RES=`s 1 "SHOW CONFIG \gx"`
RES2=`echo $RES | grep -A 3 -B 1 max_prepared_statements`
r_fake 0 $RES2

p

c 'Пусть к пулу подключится новый клиент:'

psql_open A 2 "postgresql://student@localhost:6432/student?password=student"

c 'А мы приостановим работу всех клиентов:'

s 1 "PAUSE;"

c 'Новый клиент пытается выполнить запрос:'

ss 2 "SELECT now();"
sleep 1

c 'Для него ситуация выглядит так, как будто база данных не отвечает.'

c 'Теперь мы можем даже перезапустить PostgreSQL.'

pgctl_restart A

c 'Возобновляем работу клиентов, и запрос успешно выполняется:'

s 1 "RESUME;"

r 2

c 'Таким образом можно выполнять работы на сервере БД (например, обновление), не обрывая клиентские соединения.'

P 15

###############################################################################
h 'Особенности пула транзакций'

c 'Рассмотрим на примере подготовленных операторов — в случае, когда подготовкой управляет клиент.'

psql_open A 1 "postgresql://student@localhost:6432/student?password=student"

s 1 "PREPARE hello AS SELECT 'Hello, world!';"

c 'Теперь откроем еще один сеанс.'

psql_open A 2 "postgresql://student@localhost:6432/student?password=student"

s 2 "BEGIN;"
s 2 "SELECT name, statement, prepare_time, parameter_types, result_types FROM pg_prepared_statements \gx"
s 2 "SELECT pg_backend_pid();"

c 'Транзакция второго сеанса выполняется в том же соединении, поэтому ей доступен подготовленный оператор:'

s 2 "EXECUTE hello;"

c 'А какое соединение будет использоваться в первом сеансе?'

s 1 "BEGIN;"
s 1 "SELECT pg_backend_pid();"

c 'Уже другое, поскольку во втором сеансе транзакция не завершена.'

s 1 "EXECUTE hello;"

c 'Подготовленного оператора в памяти этого обслуживающего процесса нет.'

s 1 "END;"
s 2 "END;"

c 'Чтобы пользоваться и преимуществами пула соединений, и подготовленными операторами, надо переносить управление подготовкой на сторону сервера. Самый простой и удобный способ — писать функции на языке PL/pgSQL. В этом случае интерпретатор автоматически подготавливает все запросы.'

P 17
###############################################################################
h 'Подготовка соединений и изоляция'

c 'Настройки базы данных в PgBouncer позволяют при открытии соединения выполнять любую команду SQL. Для этого добавим атрибут connect_query в строку соединения:'

e "sudo sed -i $'s/^* =.*/* = host=localhost port=5432 connect_query=\'PREPARE hello AS SELECT \'\'Привет, мир!\'\' greeting;\'/' /etc/pgbouncer/pgbouncer.ini"

c 'В конфигурационном файле получили:'
e "sudo grep '^* =' /etc/pgbouncer/pgbouncer.ini" ini

c 'Подключаемся к консоли управления и перечитываем настройки:'
s 1 "\c pgbouncer"
s 1 "RELOAD;"

c 'При открытии соединения с сервером PostgreSQL в памяти обслуживающего процесса создается подготовленный оператор:'
s 2 "\c"
s 2 "SELECT * FROM pg_prepared_statements\gx"
s 2 "EXECUTE hello;"

###############################################################################

stop_here
cleanup
demo_end
