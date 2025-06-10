#!/usr/bin/bash

# Инициализация виртуальной машины для курса

. ./environment
. ./modules/environment

SRC_VM=Course-$MAJOR
DST_VM=$course-$MAJOR-dev

# убеждаемся, что ВМ есть
if ! vboxmanage list vms | grep $SRC_VM ; then
	echo "Импортируйте ВМ $SRC_VM"
	exit 1
fi
# переименовываем в курс-версия-dev
vboxmanage modifyvm $SRC_VM --name=$DST_VM
# общая папка
vboxmanage sharedfolder add $DST_VM --name=$course --hostpath=`pwd`
# запускаем
vboxmanage startvm $DST_VM
