#!/bin/bash

# Создаёт подкаталог slides и перемещает файлы odp в него,
# а ссылки на odp заменяет правильными
#
# Нужно запускать из каталога курса:
# modules/odp2slides.sh

mkdir slides
for f in *.odp
do
	target=$(readlink $f | sed 's/modules\//..\/modules\/slides\//');
	if [[ -z $target ]]
	then
		mv $f slides/
	else
		rm $f
		ln -s $target slides/$f
	fi
done
