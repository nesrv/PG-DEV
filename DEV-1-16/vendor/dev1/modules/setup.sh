#!/usr/bin/bash

# Настройка ВМ для курсов по версии MAJOR

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

cd

# Переменные
sed -i '/^#course variables/,$d' ~/.profile
echo '#course variables' >> ~/.profile
while read line
do
	echo "export $line" >> ~/.profile
	eval "$line"
done < "${SCRIPT_PATH}/environment"

sudo apt update

# Если запустили через shared folder
sudo apt install -y git

# Обновляем сертификаты SSL
sudo apt install -y ca-certificates

# Плюшки
sudo apt install -y mc
sudo apt install -y vim
sudo apt install -y gedit mousepad gnome-calculator
sudo apt install -y tree

# Борьба с автообновлением
sudo apt purge -y unattended-upgrades
sudo rm -rf /var/log/unattended-upgrades
sudo apt purge -y update-notifier

# sudo без пароля
sudo sh -c 'echo "student ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers'

# убираем hostname из приглашения
sed -i 's/@\\h//' .bashrc

# PostgreSQL
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/apt.postgresql.org.asc
sudo apt update
sudo apt install -y postgresql-$MAJOR
# кластер main всё равно переделывать, удаляем
sudo pg_dropcluster $MAJOR main --stop

# подсветка синтаксиса
sudo apt install -y highlight recode
sudo cp modules/*.lang /usr/share/highlight/langDefs/

# документация версии MAJOR
rm -rf ~/doc
mkdir ~/doc
cd ~/doc
echo Getting documentation...
wget -e robots=off -r -k -nd -q http://repo.postgrespro.ru/doc/pgsql/$MAJOR/ru/html/index.html
cd

# трансляция терминала в локальный веб-сервер
#wget -O- https://github.com/sorenisanerd/gotty/releases/download/v1.5.0/gotty_v1.5.0_linux_amd64.tar.gz | tar zx
if [ "$ARCHITECTURE" == "amd64" ]
then
	# пока ставим gotty только для amd64
	wget -O- https://github.com/yudai/gotty/releases/download/v1.0.1/gotty_linux_amd64.tar.gz | tar zx
	cat <<- EOF >~/.gotty
	permit_write = true
	preferences {
	  background_color = "rgb(255, 255, 255)"
	  font_size = 15
	  foreground_color = "rgb(0, 0, 0)"
	  page_keys_scroll = true
	  scroll_wheel_move_multiplier = 3
	  cursor_color = "rgba(127, 127, 255, 1)"
	  ctrl_c_copy = true
	  copy_on_select = false
	}
	EOF
	# веб-страница gotty 1.x дважды обращается к локальному веб-серверу
	# чтобы демо-скрипт отрабатывал один раз, пускаем его отдельно, а из gotty подключаемся через screen
	sudo apt install -y screen
fi

# для генерации раздатки в формате html/pdf и демонстрационных скриптов
if [ "$ARCHITECTURE" == "amd64" ]
then
	# Доп. пакеты для генерации раздаточных материалов
	# ..LibreOffice настраиваем, чтобы генерация материалов работала правильно
	sudo apt install -y libreoffice
	sudo sed -i '/ExportNotesPages/{n;s/false/true/;}' /etc/libreoffice/registry/main.xcd
	# ..json parser для tweaks.json
	sudo apt install -y jq
	# ..xml tools
	sudo apt install -y xmlstarlet
	# ..конвертация pdf в html
	# sudo apt install -y pdf2htmlex # no longer packaged by debian
	wget https://github.com/pdf2htmlEX/pdf2htmlEX/releases/download/continuous/pdf2htmlEX-0.18.8.rc2-master-20200820-ubuntu-20.04-x86_64.deb
	sudo apt install -y ./pdf2htmlEX-0.18.8.rc2-master-20200820-ubuntu-20.04-x86_64.deb
	rm pdf2htmlEX-0.18.8.rc2-master-20200820-ubuntu-20.04-x86_64.deb
	# ..конвертация html в pdf
	sudo apt install -y wkhtmltopdf
	# ..pdf-утилиты, в т. ч. конвертация pdf в набор png-шек
	sudo apt install -y poppler-utils
	sudo apt install -y pdftk
fi

# в группу vboxsf, чтобы легче было цеплять shared folders в VirtualBox
if [ "$ARCHITECTURE" == "amd64" ]
then
	sudo usermod -a -G vboxsf student
fi

# Читалка для pdf
sudo apt install -y evince

# snap нужен только для firefox, удаляем его, чтобы избавиться от обновлений и сэкономить место
sudo umount /var/snap/firefox/common/host-hunspell # иногда без этого лезет ошибка
sudo snap remove --purge firefox
sudo apt purge -y snapd

# Ставим firefox из пакета и конфигурируем
sudo add-apt-repository -y ppa:mozillateam/ppa
echo '
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/mozilla-firefox

sudo apt install -y firefox

# Удаляем профиль и задаём настройки глобально
rm -rf ~/.mozilla/firefox/*

cat <<EOF | sudo tee /etc/firefox/syspref.js
pref("app.update.auto",false);
pref("browser.aboutwelcome.enabled",false);
pref("browser.laterrun.enabled",false);
pref("browser.shell.checkDefaultBrowser", false);
pref("browser.startup.firstrunSkipsHomepage",false);
pref("browser.startup.homepage", "file:///home/student/doc/index.html");
pref("browser.startup.homepage_override.mstone", "ignore");
pref("browser.startup.upgradeDialog.enabled",false);
pref("browser.translations.automaticallyPopup",false);
EOF
# Браузер по умолчанию
# но вроде и без этого работает, а firefox всё равно не понимает
#xdg-settings set default-web-browser firefox.desktop
#sudo update-alternatives --set x-www-browser /usr/bin/firefox
# а это он понимает, но открывается окно -- нехорошо:
#firefox -setDefaultBrowser

# Ярлык firefox на рабочий стол
cat <<EOF >Desktop/firefox.desktop
#!/usr/bin/env xdg-open
[Desktop Entry]
Version=1.0
Name=Firefox Web Browser
Comment=Browse the World Wide Web
GenericName=Web Browser
Keywords=Internet;WWW;Browser;Web;Explorer
Exec=firefox
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=firefox
Categories=GNOME;GTK;Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;video/webm;application/x-xpinstall;
StartupNotify=true
EOF
chmod 755 Desktop/firefox.desktop

# Скрипт и ярлык для скачивания материалов курса
cat <<'EOF' >get_handouts.sh
wget https://edu.postgrespro.ru/$MAJOR/$COURSE-handouts-$MAJOR.zip 
unzip -d $course $COURSE-handouts-$MAJOR.zip
rm $COURSE-handouts-$MAJOR.zip
EOF
chmod 755 get_handouts.sh
cat <<EOF >Desktop/get_handouts.desktop
#!/usr/bin/env xdg-open
[Desktop Entry]
Version=1.0
Type=Application
Terminal=true
Exec=/home/student/get_handouts.sh
Name=Get handouts
EOF
chmod 755 Desktop/get_handouts.desktop

# Скрипт для сброса
cp ${SCRIPT_PATH}/reset.sh ~

# Заготовка для раннего монтирования OverlayFS
cat <<'EOF' | sudo tee /etc/default/grub.d/mount-overlay.cfg > /dev/null
GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} init=/sbin/mount-overlay.sh"
EOF
sudo update-grub

cat <<EOF | sudo tee /sbin/mount-overlay.sh > /dev/null
#!/bin/sh
mount -o remount,rw /
exec /sbin/init
EOF
sudo chmod +x /sbin/mount-overlay.sh

# Лишние детали (экономим место)
sudo apt purge -y fonts-noto-cjk fonts-noto-extra # гарнитура с иероглифами, много места занимает
sudo apt autoremove -y
sudo apt clean -y
