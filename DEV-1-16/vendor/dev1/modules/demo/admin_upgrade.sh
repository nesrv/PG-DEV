#!/bin/bash

. ../lib

init

pgctl_start O
sudo -i -u postgres psql -p $PORT_O -c "CREATE USER student SUPERUSER PASSWORD 'student';"
psql -p $PORT_O -d postgres -c 'CREATE DATABASE student;'
# остается работать

# удаляем расширение pgaudit, но в кеше apt есть пакеты
sudo apt-get remove -y postgresql-$VERSION_N-pgaudit
sudo apt-get remove -y postgresql-$VERSION_O-pgaudit
sudo pg_dropcluster 16 slow

export PSQL_PROMPT1="$VERSION_N=> "
export PSQL_PROMPT2="$VERSION_O=> "

#sudo cp -r -p /var/lib/.dpkg_src/* /var/lib/dpkg

start_here 10

###############################################################################

h 'Обновление на дополнительную версию'

c 'Выясним текущую версию PostgreSQL: '

s 1 "SHOW server_version;"

MAIN_DEB="postgresql-$VERSION_N"

c 'А в репозитории есть более новая версия:'

e_fake "sudo apt list | grep '$MAIN_DEB\/'"
REPO_INFO=$(sudo apt list 2> /dev/null | grep "$MAIN_DEB\/")

c "$REPO_INFO"

VER_MINOR_O=$(echo $REPO_INFO | sed 's/.*upgradable from: \([0-9]\{2\}.[0-9]\).*/\1/')
VER_MINOR_N=$(echo $REPO_INFO | sed 's/.*\/jammy-pgdg \([0-9]\{2\}.[0-9]\).*/\1/')

c "Проведем обновление с версии $VER_MINOR_O на $VER_MINOR_N — обновим пакет '$MAIN_DEB' средствами ОС и выполним рестарт экземпляра:"

#e "sudo apt-get install -y postgresql-$VERSION_N"
e "sudo apt install postgresql-$VERSION_N -yq -o Dpkg::Progress-Fancy='0' -o APT::Color='0' -o Dpkg::Use-Pty='0'"

pgctl_restart A

c 'Проверяем номер версии:'

psql_open A 1
s 1 "SHOW server_version;"

pgctl_stop A  # чтобы случайно не подключиться

P 14

###############################################################################

h "Кластер PostgreSQL $VERSION_O"

c "В каталоге $PGDATA_O находится кластер баз данных PostgreSQL версии $VERSION_O."

psql_open O 2
s 2 "SHOW server_version;"

c 'Создадим табличное пространство и базу данных.'

e "sudo rm -rf $H/ts_dir"
e "sudo mkdir $H/ts_dir"
e "sudo chown postgres: $H/ts_dir"

s 2 "CREATE TABLESPACE ts LOCATION '$H/ts_dir';"
s 2 "CREATE DATABASE $TOPIC_DB;"
s 2 "\c $TOPIC_DB"

c 'Создадим таблицу в созданном табличном пространстве:'

s 2 "CREATE TABLE test(
  id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  s text
) TABLESPACE ts;"
s 2 "INSERT INTO test(s) VALUES ('Привет от версии $VERSION_O!');"

c 'Установим расширение pgaudit:'

# ставим из кеша apt, интернет не нужен
e "sudo apt-get install -y postgresql-$VERSION_O-pgaudit"

s 2 "ALTER SYSTEM SET shared_preload_libraries = 'pgaudit';"

pgctl_restart O

psql_open O 2

s 2 "\c $TOPIC_DB"
s 2 "CREATE EXTENSION pgaudit;"
s 2 '\dx pgaudit'

###############################################################################
h 'Утилита pg_dumpall'

c 'Сделаем резервную копию всего кластера. Сервер должен работать, но изменения, сделанные после запуска pg_dumpall, в копию не попадут.'

e "pg_dumpall -p $PORT_O > ~/dump.sql"

c 'Созданная резервная копия — текстовый файл с командами SQL. В нем есть команды для создания баз данных:'

e "grep 'CREATE DATABASE' ~/dump.sql" pgsql

c 'И команды для создания таблицы:'

e "grep -A 3 'CREATE TABLE ' ~/dump.sql" pgsql

c 'А также команды для создания таких объектов уровня кластера, как роли и табличные пространства, например:'

e "grep 'CREATE TABLESPACE' ~/dump.sql" pgsql

c "Мы не будем восстанавливать резервную копию на сервере PostgreSQL версии $VERSION_N; такое задание есть в практике."

P 18

###############################################################################
h "Кластер PostgreSQL $VERSION_N"

c "PostgreSQL версии $VERSION_N уже установлен, кластер инициализирован в каталоге $PGDATA_N."

c "Убедимся, что сервер работает и использует ту же локаль, что и PostgreSQL $VERSION_O, после чего остановим его."

s 2 "\x\l template0"
psql_close 2
pgctl_stop O

pgctl_start N
pgctl_status N

psql_open N 1 -p $PORT_N -U postgres
s 1 "\x\l template0"
s 1 "\x"

c 'Остановим сервер.'

psql_close 1
pgctl_stop N

p

###############################################################################
h 'Проверка возможности обновления'

c 'Перед тем как выполнять настоящее обновление, имеет смысл запустить pg_upgrade в режиме проверки с ключом --check. Мы планируем не копировать файлы данных, а использовать ссылки, поэтому указываем и ключ --link.'

c 'Также мы должны указать пути к исполняемым файлам и к каталогу данных как для старой версии, так и для новой. Обратите внимание, что программа запускается от имени пользователя ОС postgres, так как ей требуется доступ к каталогам данных.'

c 'Следует обратить внимание на настройки доступа. Утилита в процессе работы запускает и останавливает серверы, и для этого нужно, чтобы к обоим кластерам у нее был локальный суперпользовательский доступ.'\
' У нас такой доступ есть, а в общем случае может потребоваться временно изменить файл pg_hba.conf. Также программа pg_upgrade создаёт различные временные файлы в специально создаваемом рабочем каталоге'\
' pg_upgrade_output.d внутри каталога данных нового кластера, доступ на запись к которому ей тоже необходим.'\
' Серверы поднимаются по очереди на порту 50432, чтобы не допустить случайного подключения к ним пользователей; при необходимости номер порта можно указать явно.'

eu postgres "${BINPATH_N}pg_upgrade --check --link -b $BINPATH_O -B $BINPATH_N -d $CONF_O -D $CONF_N"

c 'Ошибка возникла из-за того, что версии задействованных в обновлении исполняемых файлов (initdb, pg_dump, pg_dumpall, pg_restore, psql, vacuumdb, pg_controldata, postgres) не соответствуют версии самой утилиты pg_upgrade.'

p

c 'Выполним обновление соответствующего пакета и повторим попытку:'

e "sudo apt-get install -y postgresql-client-$VERSION_N"

eu postgres "${BINPATH_N}pg_upgrade --check --link -b $BINPATH_O -B $BINPATH_N -d $CONF_O -D $CONF_N"

c 'Утилита снова обнаружила проблему: в новом кластере не хватает библиотек.'

c 'Посмотрим их список:'

INFOFILE=$(sudo find $PGDATA_N/pg_upgrade_output.d -type f -name loadable_libraries.txt)
e "sudo cat $INFOFILE"

c "Это библиотека установленного нами расширения, от которого зависит индекс в базе $TOPIC_DB. Ее необходимо установить и в новом кластере."

# ставим из кеша apt, интернет не нужен
e "sudo apt-get install -y postgresql-$VERSION_N-pgaudit"

c 'Не забываем дать указание загружать библиотеку в память каждого обслуживающего процесса:'

pgctl_start N
psql_open N 1 -U postgres
s 1 "ALTER SYSTEM SET shared_preload_libraries = 'pgaudit';"
pgctl_stop N

c 'Проверяем еще раз.'

eu postgres "${BINPATH_N}pg_upgrade --check --link -b $BINPATH_O -B $BINPATH_N -d $CONF_O -D $CONF_N"

c 'Теперь кластеры совместимы.'

P 21

###############################################################################
h 'Обновление'

c 'Выполняем обновление в режиме создания ссылок.'

eu postgres "${BINPATH_N}pg_upgrade --link -b $BINPATH_O -B $BINPATH_N -d $CONF_O -D $CONF_N"

c 'Перед запуском сервера следовало бы перенести изменения, сделанные в конфигурационных файлах старого сервера, на новый. Мы не будем этого делать, поскольку работаем с настройками по умолчанию.'

c 'Итак, проверим результат.'

pgctl_start N
psql_open N 1
s 1 "SHOW server_version_num;"

s 1 "\c $TOPIC_DB"
s 1 "SELECT * FROM test;"

c 'Обновление прошло успешно: нам доступно содержимое старого кластера.'

p

###############################################################################
h 'Табличные пространства'

c 'Посмотрим на файлы табличного пространства:'

e "sudo tree $H/ts_dir --inodes"

ul 'Внутри каталога создается подкаталог для каждой версии, поэтому пересечения по файлам не происходит.'
ul 'Как видно по числу в квадратных скобках (inode), файлы в каталогах старой и новой версий на самом деле разделяют общее содержимое.'

p

###############################################################################
h 'Действия после обновления'

c 'Библиотеки установленных расширений заменяются при установке новой версии, но на уровне объектов баз данных версия расширения остается неизменной:'

s 1 '\dx pgaudit'

c 'Утилита обнаружила этот факт и сгенерировала скрипт, обновляющий расширения во всех базах данных:'

e "sudo cat $H/update_extensions.sql" pgsql

c 'Выполним его.'

e "sudo psql -U postgres -p $PORT_N -f $H/update_extensions.sql"

c 'В нашем случае разработчики расширения не предоставили скрипт для обновления версии, поэтому придется удалить расширение и установить его заново.'

s 1 'DROP EXTENSION pgaudit;'
s 1 'CREATE EXTENSION pgaudit;'
s 1 '\dx pgaudit'

c 'Утилита pg_upgrade сгенерировала еще один скрипт. Это скрипт для удаления старых данных:'

e "sudo cat $H/delete_old_cluster.sh" sh

c 'Кроме этого, по завершении процесса обновления она выдала подсказку о необходимости выполнения сбора статистики:'

e 'echo "/usr/lib/postgresql/16/bin/vacuumdb --all --analyze-in-stages"'

###############################################################################

stop_here
cleanup
demo_end
