#!/usr/bin/bash

# Экспорт виртуальной машины курс-версия-dev в ova

. ./environment
. ./modules/environment

VMNAME=$course-$MAJOR-dev

# убеждаемся, что ВМ есть
(vboxmanage list vms | grep $VMNAME) || (echo "ВМ $VMNAME не найдена";exit 1)

# ресурсы
vboxmanage modifyvm $VMNAME --vram=128 --cpus=1 --memory=$VM_RAM

# удаляем shared folders
for f in $(VBoxManage showvminfo $VMNAME --machinereadable | grep '^SharedFolderNameMachineMapping' | grep -o '".*"' | tr -d '"')
do
	VBoxManage sharedfolder remove $VMNAME --name=$f
done

# экспорт
vboxmanage export $VMNAME \
--vsys=0 \
--vmname=$COURSE-$MAJOR-`date +%Y%m%d` \
--output $COURSE-$MAJOR-`date +%Y%m%d`.ova \
--version="$MAJOR - `date +%d.%m.%Y`" \
--ovf10 \
--manifest \
--product="$VM_PRODUCT" \
--producturl="https://postgrespro.ru/education/courses/$COURSE" \
--vendor="Postgres Professional" \
--vendorurl="https://postgrespro.ru" \
--eulafile=${course}_eula.txt
