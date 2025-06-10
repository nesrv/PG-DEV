#!/bin/bash

# Скрипт удаляет верхний слой каталогов, заданных в OVERLAY_DIRS, и чистит ~student/tmp.
# В конце выполняет команду, заданную в переменной POST_RESET
# (обычно запуск основного экземпляра postgres).

prnusage() {
	cat <<- USG
	This script reverts ${OVERLAY_DIRS// /, } to the initial state and removes ~/tmp.
	Usage:
	  ./reset.sh
	USG
}

if [ $# -ne 0 ]; then
	prnusage
	exit 1
else
	# Останавливаем кластеры PostgreSQL
	echo stopping postgresql clusters...
	pg_lsclusters -h | grep -Eo '^[0-9]{2} [[:alnum:]]+' | while read cluster ; do
		sudo pg_ctlcluster $cluster stop > /dev/null
	done

	# Завершаем процессы пользователя postgres
	echo stopping processes running as postgres...
	sudo killall -QUIT -u postgres >& /dev/null
	# Стираем workdir и upper для всех каталогов OverlayFS
	for target in $OVERLAY_DIRS
	do
		echo "resetting ${target}..."
		basename=${target//\//_}
		sudo umount -q $target
		sudo rm -rf /var/lib/.reset/$basename/{upper,work}
		sudo mkdir -p /var/lib/.reset/$basename/{upper,work}
		sudo chown -R postgres: /var/lib/.reset/$basename/{upper,work}
		sudo mount $target
	done

	# Чистим ~student/tmp
	echo "cleaning up ~student/tmp..."
	sudo rm -rf ~student/tmp
	mkdir ~student/tmp

	# post reset
	echo running post-reset action: ${POST_RESET}...
	eval ${POST_RESET}
fi
