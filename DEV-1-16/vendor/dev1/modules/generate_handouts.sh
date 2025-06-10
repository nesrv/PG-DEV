#!/bin/bash

########################################################################
#
# 1. Импортируем ВМ курса
#
# ----------
#
# 2. Доступ к репозиторию.
#
# Вариант a: Клонируем репозиторий
#
#	Запускаем виртуалку и в ней:
#
#	course=... # нижний регистр
#	git clone https://pubgit.postgrespro.ru/edu/$course.git --recurse-submodules --branch $MAJOR
#
# Вариант b: Настраиваем доступ из ВМ к репозиторию на хосте
#
#	На хосте в каталоге репозитория курса:
#	. modules/environment
#	. environment
#	vboxmanage sharedfolder add $course-$MAJOR-dev --name=$course --hostpath=`pwd` --automount
#	vboxmanage startvm $course-$MAJOR-dev
#
#	В виртуалке:
#	ln -s /media/sf_${course} ~/${course}
#
# ----------
#
# 3. Запускаем генерацию
#
# ~/$course/generate_handouts.sh
#
########################################################################

if [[ ! (`whoami` =~ student) ]]; then
    echo "! Run me as student"
    exit 1
fi
if [[ "$COURSE" == "" ]]; then
    echo "! COURSE is not set"
    exit 1
fi
if [[ "$MAJOR" == "" ]]; then
    echo "! MAJOR is not set"
    exit 1
fi

if ps -e | grep soffice; then
    echo "! Close LibreOffice"
    exit 1
fi

if ps -e | grep psql; then
    read -p "Запущен PSQL! Нажмите Enter для продолжения генерации, n для прерывания:" answer
	case $answer in
	n) exit 1;;
	esac
fi

# Файл с ошибками
export ERRFILE=$(pwd)/generate_handouts.err
rm -f $ERRFILE

cd ~/$course

if [[ -d modules ]]; then
    modules=modules
elif [[ -d modules-en ]]; then
    modules=modules-en
else
    echo "! No modules/ or modules-en/"
    exit 1
fi

# Можно задать имя файла, чтобы сгенерировать раздатку только для него
# (удобно для отладки)
if [ "$1" == "" ]; then
    FILEPATTERN=$course_*
else
    single=`basename $1`
    FILEPATTERN=${single%.*}*
fi

prepare_dir() {
    if [ -d $1 ]; then
	rm -rf $1/*;
    else
	mkdir $1
	chmod 777 $1
    fi
}
prepare_dir 'tmp'           # временные файлы, нужные для конвертаций
prepare_dir 'handouts'      # раздаточные материалы
prepare_dir 'handouts/pdf'
prepare_dir 'presentation'  # презентации для преподавателя

# Обрабатываем слайды и формируем .ctl:
# строка 1: название темы
# строка 2: карта слайдов (массив тегов)
# строка 3: страницы demo (массив номеров)
process_slides() {
	echo "processing slides"
	# xpaths for page 1
	declare module_xpath='/draw:frame/draw:text-box/text:p/text:span[@text:style-name="T1"]'
	declare topic_xpath='/draw:frame/draw:text-box/text:p/text:span[@text:style-name="T2" and not(text:line-break)]'
	declare titlebox_xpath='//draw:frame[@presentation:class="title"]/draw:text-box'
	for odp in slides/$FILEPATTERN.odp; do
		declare name=$(basename -s .odp $odp)
		cp $odp tmp/$name.odp
		unzip -p tmp/$name.odp content.xml > tmp/content.xml
		# tweaks
		if [ -f tweaks.json ]; then
			topic_tweaks=$(jq -r ".$name" tweaks.json)
			if [ "$topic_tweaks" != null ]; then
				echo "...   tweaking $name.odp"
				# replace module name
				new_module=$(jq -r ".$name.module" tweaks.json)
				if [ "$new_module" != "" ]; then
					xmlstarlet ed \
						--pf \
						--ps \
						--inplace \
						--update '////draw:page[@draw:name="page1"]'"${module_xpath}" \
						--value "${new_module}" \
						tmp/content.xml
					zip -j tmp/$name.odp tmp/content.xml
				fi
			fi
		fi
		# extract control info
		echo "...   $name.odp => $name.ctl"
		declare -a slidemap=()
		declare -a demopages=()
		# iterate over pages
		for p in `xmlstarlet sel -t -m '////draw:page' -v './@draw:name' -nl tmp/content.xml`; do
			declare -i page_num=${p:4}
			declare tag=''
			# page contents
			page_xpath='////draw:page[@draw:name="page'$page_num'"]'
			page=`xmlstarlet sel -t -c $page_xpath -nl tmp/content.xml`
			if [[ $page_num = 1 ]]; then
				# extract module, topic, title
				module=$(xmlstarlet sel -t -m "$page_xpath""$module_xpath" -v 'concat(.,"")' tmp/content.xml)
				topic=$(xmlstarlet sel -t -m "$page_xpath""$topic_xpath" -v '.' tmp/content.xml)
			else
				# page title
				title=$(xmlstarlet sel -t -v "$page_xpath""$titlebox_xpath" -t -m "$page_xpath"'//draw:g[@draw:name="book"]' -v './@draw:name' tmp/content.xml)
				#echo $title
				case "$title" in
				Демонстрация)
					tag=demo ;;
				Практика)
					tag=lab ;;
				Практикаbook) # title is followed by book image
					tag=app ;;
				Практика+)
					tag=opt ;;
				esac
			fi
			case $tag in
			demo)
				slidemap+=(demo)
				demopages+=($page_num)
				;;
			lab|app|opt)
				# check if solution exists
				declare ifbase=${odp##*/}
				declare ifname=${ifbase%.*}
				declare labfile=labs/${ifname}_${tag}.sh
				if [ -f $labfile ]; then
					slidemap+=($tag)
				else
					slidemap+=(-)
				fi
				;;
			*)
				slidemap+=(+)
			esac
		done
		echo "${module}. ${topic}" > tmp/$name.ctl
		echo "${slidemap[*]}" >> tmp/$name.ctl
		echo "${demopages[*]}" >> tmp/$name.ctl
		rm tmp/content.xml
	done
}
process_slides

# Для включения в pdf файлы заметок к слайдам:
sudo sed -i '/ExportNotesPages/{n;s/false/true/;}' /etc/libreoffice/registry/main.xcd
#
# ! Во время работы скрипта LibreOffice не должен быть запущен, иначе ничего не происходит.
#

soffice --headless --convert-to pdf --outdir tmp tmp/$FILEPATTERN.odp

# Предварительная проверка: если хотя бы один pdf-файл оказался с нечетным числом страниц,
# то выставлены неправильные настройки. Это не 100% надежно, но хоть что-то.
cd tmp
for INPUT_PDF in `find . -regex "./${course}_[0-9][0-9]_[a-z0-9_]*.pdf"`; do
    NUMPAGES=`pdftk $INPUT_PDF dump_data | grep NumberOfPages | sed 's/[^0-9]//g'`
    if (( $NUMPAGES % 2 )); then
        echo "! Check LibreOffice PDF export settings ($INPUT_PDF has odd number of pages)"
        exit 1
    fi
done
cd ..

# актуальные настройки подсветки синтаксиса
sudo cp $modules/*.lang /usr/share/highlight/langDefs/

#
# Обработка демонстраций и практик
#
# - генерируем html из скрипта;
# - режем html на отдельные фрагменты-листинги;
# - каждый фрагмент обертываем шаблоном, чтобы получится корректный html с нужными стилями;
# - и затем конвертируем в pdf.
# Результат в виде html нужен для html-версии раздатки, а pdf - для pdf-версии.
#
process_scripts() {
    dir=$1
    cd $dir
    for filename in `ls -1 ${FILEPATTERN}.sh`; do
        name=`basename -s .sh $filename`
        echo "====="
        echo "$dir: $filename -> ../tmp/$name.html"
        echo "====="
        ./$filename --non-interactive --html >../tmp/$name.html

        # обработка листинга
        declare -a demopages
        if [ $dir = 'demo' ]; then
     		demopages=$(cat ../tmp/$name.ctl | head -n 3 | tail -n 1)
        else
            demopages='0'
        fi
        for i in ${demopages[*]}; do
            # отрезаем от листинга фрагмент
            body_html="../tmp/`basename -s .sh $filename`-$i-body.html"
            if [ $dir = 'demo' ]; then
                mark=$i
            else
                mark='.*' # в практиках нам не важно, как помечен фрагмент - он один
            fi
            echo "...   $i -> $body_html"
            sed -n "/<\!-- $mark -->/,/<\!-- end -->/p" ../tmp/$name.html > $body_html

            # оборачиваем фрагмент в заготовленный шаблон
            page_html="../tmp/`basename -s .sh $filename`-$i.html"
            echo "...   -> $page_html"
            cp ../$modules/template_listing.html $page_html
            sed -i -e "/<\!-- body -->/r $body_html" $page_html

            # конвертируем html-страничку в pdf
            page_pdf="../tmp/`basename -s .sh $filename`-$i.pdf"
            echo "...   -> $page_pdf"
            wkhtmltopdf -L 10mm -R 10mm -T 10mm -B 10mm $page_html $page_pdf
            sleep 1 # иначе получаем пустые pdf-ки (почему?!)
        done
    done
    cd ..
}
process_scripts 'demo'
process_scripts 'labs'

#
# Из pdf-презентаций + демо + практики делаем:
# - html-презентацию для преподавателей;
# - раздатки (html и pdf) для слушателей.
#
build() {
	cd tmp
	for INPUT_PDF in `find . -regex "./${course}_[0-9][0-9]_[a-z0-9_]*.pdf" | sort`; do
		local ifbase=${INPUT_PDF##*/}
		local ifname=${ifbase%.*}
		# рубим pdf надвое: слайды отдельно, заметки отдельно
		echo "===="
		echo "tmp: $INPUT_FILE"
		echo "===="
		local SLIDES_PDF="$ifname-slides.pdf"
		local NOTES_PDF="$ifname-notes.pdf"
		local NUMPAGES=`pdftk $INPUT_PDF dump_data | grep NumberOfPages | sed 's/[^0-9]//g'`
		echo "...  #pages = $NUMPAGES, split to $SLIDES_PDF and $NOTES_PDF"
		pdftk $INPUT_PDF cat 1-$(($NUMPAGES/2)) output $SLIDES_PDF
		pdftk $INPUT_PDF cat $(($NUMPAGES/2+1))-end output $NOTES_PDF

		# из слайдов делаем html-презентацию

		# конвертируем pdf в набор png-шек (с параметрами по умолчанию получаем 1655x1240 px - с запасом)
		echo "tmp: pdftocairo -png $SLIDES_PDF _$ifname"
		pdftocairo -png $SLIDES_PDF _$ifname # на выходе получим $ifname-N.png или $ifname-NN.png
		local PRES="../presentation/$ifname.html"
		echo "tmp: presentation -> $PRES"
		cp ../$modules/template_presentation.html $PRES
		# из ctl-файла берем тему и карту слайдов
		declare module_topic=$(cat $ifname.ctl | head -n 1)
		declare -a slidemap=($(cat ../tmp/$ifname.ctl | head -n 2 | tail -n 1))
		# вставляем картинки
		declare -i slide_n=0
		declare -i page_n=0
		for tag in ${slidemap[@]}; do
			slide_n+=1
			declare slide_nn=`printf '%02d' ${slide_n}`
			# если число страниц от 1 до 9, номера однозначные
			# а если от 10 до 99 - двузначные
			declare png=_${ifname}-${slide_nn}.png
			declare png1=_${ifname}-${slide_n}.png
			if [ ! -f "$png" ]; then
				png="$png1"
			fi
			# if page is to be skipped
			if [[ "$tag" = "-" ]]; then
				echo "...  $png (${slide_nn}:skipping)"
			else
				# упаковываем png в base64 и вставляем в шаблон на нужное место
				page_n+=1
				declare page_nn=`printf '%02d' ${page_n}`
				echo "...  $png (${slide_nn}:${page_nn})"
				local PNG64=`base64 -w 0 $png`
				sed -i -f - $PRES <<-EOF # в одну строку не получается, т. к. base64 большой
					s@{{${page_nn}}}@$PNG64@
				EOF
			fi
		done
		# вставляем количество слайдов
		echo "...  number of pages = $page_n"
		sed -i "s/{{numpages}}/$page_n/" $PRES
		# подставляем тему, название курса и demopages в шаблон
		echo "...  topic = $module_topic"
		sed -i "s@{{course}}@$COURSE@" $PRES
		sed -i "s@{{topic}}@$module_topic@" $PRES
		declare demopages=$(cat ../tmp/$ifname.ctl | head -n 3 | tail -n 1)
		echo "...  demopages = $demopages"
		sed -i "s/{{demopages}}/${demopages// /,}/" $PRES
		# убираем лишние заготовки (в которые ничего не подставилось)
		echo "...  removing excessive stubs"
		sed -i '/{{[0-9][0-9]}}/d' $PRES

		# к презентации добавляем sh для автозапуска gotty и браузера

		local PRESSH="../presentation/$ifname.sh"
		echo "tmp: presentation sh -> $PRESSH"
		echo "../$modules/present.sh $ifname" > $PRESSH
		chmod a+x $PRESSH
		chmod -x $PRES

		# из заметок делаем html-раздатку

		local HANDOUT_HTML="../handouts/$ifname.html"
		echo "tmp: pdf2htmlEX $NOTES_PDF $HANDOUT_HTML"
		pdf2htmlEX --tounicode 1 $NOTES_PDF $HANDOUT_HTML
		echo "...  postprocessing $HANDOUT_HTML"

		local URLS='[[:alpha:]0-9@/.\_#=?;-]*' # sed
		local URLP='[[:alpha:]0-9@\/._\-#=?;]*' # perl

		# Пустые span-ы удалять нельзя - съезжает расположение некоторых надписей.
		# Но в url-ах мы их все-таки удаляем, чтобы иметь возможность сделать url кликабельным
		# Сначала внутри заголовка http...
		sed -i 's/\(h\)<span [^>]*><\/span>\(ttps\?:\)/\1\2/g' $HANDOUT_HTML
		sed -i 's/\(ht\)<span [^>]*><\/span>\(tps\?:\)/\1\2/g' $HANDOUT_HTML
		sed -i 's/\(htt\)<span [^>]*><\/span>\(ps\?:\)/\1\2/g' $HANDOUT_HTML
		sed -i 's/\(http\)<span [^>]*><\/span>\(s\?:\)/\1\2/g' $HANDOUT_HTML
		sed -i 's/\(https\?\)<span [^>]*><\/span>\(:\)/\1\2/g' $HANDOUT_HTML
		# + еще один клинический случай в dba3
		sed -i 's/\(ht\)<span [^>]*><\/span>\(tps\?\)<span [^>]*><\/span>\(:\)/\1\2\3/g' $HANDOUT_HTML
		# ...а потом и после, когда уже уверены, что это действительно url
		while : ; do
			sed -i 's/\(https\?:'$URLS'\)<span [^>]*><\/span>/\1/gw changes' $HANDOUT_HTML
			if ! [ -s changes ]; then
				break
			fi
		done
		# и для двустрочных url-ов...
		while : ; do
			sed -i 's/\(<div [^>]*>\)\(https\?:'$URLS'\)\(<\/div><div [^>]*>\)\('$URLS'\)<span [^>]*><\/span>/\1\2\3\4/gw changes' $HANDOUT_HTML
			if ! [ -s changes ]; then
				break
			fi
		done
		# кликабельный email
		sed -i 's/\(edu@.*ru\)/<a href="mailto:edu@postgrespro.ru" style="text-decoration: none;">edu@postgrespro.ru<\/a>/g' $HANDOUT_HTML
		# кликабельный url на двух строках
		perl -CSD -pi -e 's/(<div [^>]*>)(https?:'$URLP')(<\/div><div [^>]*>)('$URLP')(<\/div>)/\1<a href="\2\4" target="_blank" style="text-decoration: none;">\2<\/a>\3<a href="\2\4" target="_blank" style="text-decoration: none;">\4<\/a>\5/g' $HANDOUT_HTML
		# кликабельный url (не трогаем уже "закавыченные" и внутри <a>...</a>)
		perl -CSD -pi -e 's/(?<!")(?<!none;">)(https?:'$URLP')/<a href="\1" target="_blank" style="text-decoration: none;">\1<\/a>/g' $HANDOUT_HTML

		# удаляем ненужные задания и вставляем ответы
		slide_n=0
		for tag in ${slidemap[*]}; do
			slide_n+=1
			declare pattern="data-page-no=\"`printf '%x' $slide_n`\""
			case "$tag" in
			+) # с нормальными слайдами ничего не делаем
				;;
			demo) # демо-слайд заменяем на фрагмент демонстрации
				# pdf2htmlEX использует шестнадцатеричные номера страниц
				local h=`printf '%x\n' $slide_n`
				echo "...  inserting demo page $h"
				# сначала заменяем фрагмент, сгенерированный pdf2htmlEX, на наш собственный
				local PATTERN='<div id="pf'$h'".*' # один слайд = одна строка
				local REPLACE='<div id="pf'$h'" class="pf w0 h0" data-page-no="'$h'"><div class="pc w0 h0"><object data="data:text/html;base64,{{page}}" type="text/html" style="width:100%;height:100%;overflow:auto;"></object></div><div class="pi" data-data='"'"'{"ctm":[1.000000,0.000000,0.000000,1.000000,0.000000,0.000000]}'"'"'></div></div>'
				sed -i -f - $HANDOUT_HTML <<-EOF
					s@$PATTERN@$REPLACE@
				EOF
				# затем подставляем в наш фрагмент base64 страницы демо
				local PAGE64=`base64 -w 0 ${ifname}-${slide_n}.html`
				sed -i -f - $HANDOUT_HTML <<-EOF # в одну строку не получается, т. к. base64 большой
					s@{{page}}@$PAGE64@
				EOF
				;;
			-) # удаляем страницу с заданием без решения
				echo "...  deleting page $slide_n - no solution"
				sed -i "/${pattern}/d" $HANDOUT_HTML
				;;
			*) # вставляем решение
				echo "...  inserting solution for ${tag} after page ${slide_n}"
				declare solution_line='<div id="pf'${tag}'" class="pf w0 h0" data-page-no="'${tag}'"><div class="pc w0 h0"><object data="data:text/html;base64,{{page}}" type="text/html" style="width:100%;height:100%;overflow:auto;"></object></div><div class="pi" data-data='"'"'{"ctm":[1.000000,0.000000,0.000000,1.000000,0.000000,0.000000]}'"'"'></div></div>'
				sed -i "/${pattern}/a ${solution_line}" $HANDOUT_HTML
				# подставляем в наш фрагмент base64 страницы ответов
				declare PAGE64=`base64 -w 0 ${ifname}_${tag}-0.html`
				sed -i -f - $HANDOUT_HTML <<-EOF # в одну строку не получается, т. к. base64 большой
					s@{{page}}@$PAGE64@
				EOF
			esac
		done

		# pdf-раздатка

		local HANDOUT_PDF="../handouts/pdf/$ifname.pdf"
		local CATLIST=$(seq 1 $(($NUMPAGES/2))) # все страницы NOTES_PDF
		local LISTINGS=
		local HANDLE=A
		# пробегаем по слайдам
		slide_n=0
		for tag in ${slidemap[*]}; do
			slide_n+=1
			case "$tag" in
			+) # с нормальными слайдами ничего не делаем
				;;
			demo) # демо добавляем в список входных файлов
				CATLIST=`echo $CATLIST | sed "s/\b${slide_n}\b/$HANDLE/"` # меняем номера демо-страниц на handle листинга
				LISTINGS="$LISTINGS $HANDLE=${ifname}-${slide_n}.pdf"
				HANDLE=`echo $HANDLE | tr '[A-Y]Z' '[B-Z]A'` # increment
				;;
			-) # удаляем страницу с заданием без решения
				CATLIST=`echo $CATLIST | sed "s/\b${slide_n}\b//"`
				;;
			*) # добавляем решение
				CATLIST=`echo $CATLIST | sed "s/\b${slide_n}\b/${slide_n} $HANDLE/"` # дописываем handle листинга после слайда практики
				LISTINGS="$LISTINGS $HANDLE=${ifname}_${tag}-0.pdf"
				HANDLE=`echo $HANDLE | tr '[A-Y]Z' '[B-Z]A'` # increment
			esac
		done
		echo "...  pdftk $NOTES_PDF $LISTINGS cat $CATLIST output $HANDOUT_PDF"
		pdftk $NOTES_PDF $LISTINGS cat $CATLIST output $HANDOUT_PDF
	done
	cd ..
}
build

# Справочные материалы берем из extras/
# Student guide и New features тоже конвертируем здесь
if [ "$1" == "" ]; then
	echo
	echo processing extras and guides
	for INPUT_FILE in $(ls extras/*.od? 2>/dev/null) ${course}_student_guide.odt ${course}_new_features.odt;
	do
		soffice --headless --convert-to pdf --outdir handouts $INPUT_FILE
	done
fi

ZIP=$COURSE-handouts-$MAJOR-`date +%Y%m%d`.zip
cd handouts
zip -r $ZIP *
mv $ZIP ..
cd ..

# Проверяем, были ли ошибки
echo
if [ -s $ERRFILE ]; then
	echo "vvvvv Generation errors vvvvv"
	cat $ERRFILE
	echo "^^^^^ Generated with errors ^^^^^"
else
	echo "Generated"
fi
