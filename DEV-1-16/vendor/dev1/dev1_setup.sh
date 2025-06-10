#!/usr/bin/bash

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

. ${SCRIPT_PATH}/modules/course_setup_prologue.sh

# PostgreSQL extensions
sudo apt install -y postgresql-plperl-$MAJOR
sudo apt install -y postgresql-$MAJOR-pldebugger
sudo apt install -y postgresql-$MAJOR-plpgsql-check

# pgAdmin
if [ "$ARCHITECTURE" == "amd64" ]
then
	wget --quiet -O - https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor --yes -o /usr/share/keyrings/packages-pgadmin-org.gpg
	sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list'
	sudo apt update
	sudo apt install -y pgadmin4-desktop
	sudo apt install -y sqlite3 # пригодится, см. readme
	cat << EOF > Desktop/pgadmin4.desktop
[Desktop Entry]
Version=1.0
Encoding=UTF-8
Name=pgAdmin 4
Exec=/usr/pgadmin4/bin/pgadmin4
Icon=pgadmin4
Type=Application
Categories=Application;Development;
MimeType=text/html
Comment=Management tools for PostgreSQL
Keywords=database;db;sql;query;administration;development;
EOF
	chmod 755 Desktop/pgadmin4.desktop
fi

# кластер
sudo pg_createcluster $MAJOR main --start -- --auth-local=trust --auth-host=scram-sha-256

# пользователь и база student (для входа по умолчанию без правки pg_hba)
sudo -i -u postgres psql -c "CREATE USER student SUPERUSER PASSWORD 'student';"
sudo -i -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"
psql -d postgres -c 'CREATE DATABASE student;'

# приложение
sudo apt install -y php-pgsql
sudo apt install -y apache2
sudo apt install -y libapache2-mod-php
rm -rf ~/dev1app
git clone https://pubgit.postgrespro.ru/pub/dev1app.git
cd ~/dev1app
git checkout $MAJOR
cd

sudo cp -r ~/dev1app/* /var/www/html/
rm -rf ~/dev1app
sudo cp /var/www/html/config.php.example /var/www/html/config.php
sudo service apache2 restart

# настройки psql
cat <<EOF >>.psqlrc
\setenv PAGER 'less -XS'
\set PROMPT1 '%n/%/%R%x%# '
\set PROMPT2 '%n/%/%R%x%# '
EOF

. ${SCRIPT_PATH}/modules/course_setup_epilogue.sh
