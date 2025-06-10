#!/bin/bash

. ../lib

init

start_here 8

###############################################################################
h 'XML: тип xml'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s_bare 1 "\pset xheader_width $WIDTH" > /dev/null  # м.б. вытащить в params?

c 'Будем работать с документом, описывающим компоненты компьютера.'

ul 'Теги выделяются угловыми скобками. Для каждого открывающего тега (<computer>) есть соответствующий ему закрывающий, имя которого начинается на косую черту (</computer>). Такая пара тегов определяет элемент (computer).'
ul 'Атрибуты могут быть перечислены вместе со значениями в открывающем теге.'
ul 'Текст внутри тегов составляет текстовый элемент.'

s 1 "SELECT \$xml\$
<computer>                                <!-- открывающий тег -->
  <motherboard>
    <!-- текстовый элемент -->
    <cpu>Intel® Core™ i7-7567U</cpu>
    <ram>
      <!-- тег с атрибутом -->
      <dimm size_gb=\"32\">Crucial DDR4-2400 SODIMM</dimm>
    </ram>
  </motherboard>
  <disks>
    <ssd size_gb=\"512\">Intel 760p Series</ssd>
    <hdd size_gb=\"3000\">Toshiba Canvio</hdd>
  </disks>
</computer>                               <!-- закрывающий тег -->
\$xml\$ AS xml \gset"

c 'В PostgreSQL имеется тип xml, значение которого хранится в виде символьной строки, а при приведении к типу происходит проверка структуры. В зависимости от значения параметра xmloption проверка ожидает:'
ul 'document — документ (с одним корнем),'
ul 'content — фрагмент документа (любой набор элементов).'

s 1 "SHOW xmloption;"

c 'При приведении к типу xml форматирование сохраняется:'
s 1 "SELECT :'xml'::xml;"

c 'А попытка привести некорректный фрагмент даст ошибку:'
s 1 "SELECT '<tag>wrong xml<tag>'::xml;"

p
###############################################################################
h 'XML: выражения XPath'

c 'Посмотрим, какие средства есть для получения части XML-документа. Для этого используются выражения языка запросов XPath 1.0. Мы не будем детально рассматривать все возможности XPath, но посмотрим некоторые примеры.'

c 'XML состоит из иерархии элементов, поэтому язык описывает перемещения по дереву. Часть документа, соответствующая пути от корня:'

s 1 "SELECT xpath('/computer/motherboard/ram', :'xml');"

c 'В пути можно указывать не только непосредственные потомки:'

s 1 "SELECT xpath('/computer//ram', :'xml');"

#c 'И даже так:'
#
#s 1 "SELECT xpath('//ram', :'xml');"

c 'По дереву элементов можно «двигаться» не только вниз к листьям, но и вверх к корню:'

s 1 "SELECT xpath('//ram/dimm/..', :'xml');"

c 'Вместо конкретного имени элемента можно указать, что подходит любой:'

s 1 "SELECT xpath('//disks/*', :'xml') \gx"

c 'Здесь мы получили в массиве две части XML-документа. Можно посчитать количество:'

s 1 "SELECT xpath('count(//disks/*)', :'xml');"

c 'Можно извлечь не весь элемент, а только его текст:'

s 1 "SELECT xpath('//cpu/text()', :'xml');"

c 'Атрибуты записываются с помощью «собаки». Найдем значения атрибутов size_gb:'

s 1 "SELECT xpath('//@size_gb', :'xml');"

#c 'А так можно посчитать суммарный объем дисковой памяти:'
#
#s 1 "SELECT xpath('sum(//disks//@size_gb)', :'xml');"

c 'Условия фильтрации записываются в квадратных скобках. Найдем все элементы, объем памяти которых начинается от 1000 гигабайт:'

s 1 "SELECT xpath('//*[@size_gb >= 1000]', :'xml');"

c 'Сравнение работает, потому что XPath поддерживает числовые типы. Кроме этого, поддерживаются строки и логический тип.'

c 'Выражения XPath применяются не только в функции xpath, но и в других. Например, можно проверить, содержит ли XML-документ указанный фрагмент:'

s 1 "SELECT xmlexists(
    '//disks/*[starts-with(text(),''Toshiba'')]'
    PASSING :'xml'
);"
s 1 "SELECT xmlexists(
    '//disks/*[starts-with(text(),''Seagate'')]'
    PASSING :'xml'
);"

p

###############################################################################
h 'XML: преобразование в реляционный вид и обратно'

c 'Для того чтобы преобразовать XML-документ к реляционному (табличному) виду, используется функция xmltable.'
c 'Пусть у нас имеется таблица для дисковых накопителей:'

s 1 "CREATE TABLE disks (
    drive_type text,
    name text,
    capacity integer
);"

c 'Сначала выделим нужную часть документа:'

s 1 "SELECT xpath('//disks/*', :'xml');"

c 'Теперь можно написать вызов функции xmltable. В нем мы указываем выражение XPath, сам документ, а также описываем, как получать значения для столбцов таблицы с помощью дополнительных XPath-выражений:'

s 1 "SELECT * FROM xmltable(
    '//disks/*'
    PASSING :'xml'
    COLUMNS
        drive_type  text PATH 'name()',
        name        text PATH 'text()',
        capacity integer PATH '@size_gb * 1024'
);"

c 'Обратите внимание:'
ul 'выражения XPath для столбцов отсчитываются не от корня документа, а от текущего контекста (элемента, найденного основным выражением XPath);'
ul 'в выражениях можно использовать некоторые арифметические операции.'

c 'Результат такого запроса можно непосредственно вставить в таблицу:'

s 1 "INSERT INTO disks(drive_type, name, capacity)
SELECT * FROM xmltable(
    '//disks/*'
    PASSING :'xml'
    COLUMNS
        drive_type  text PATH 'name()',
        name        text PATH 'text()',
        capacity integer PATH '@size_gb * 1024'
);"

p

c 'Для создания документов XML имеется довольно много функций, с помощью которых можно собрать документ «по кусочкам». Но есть также функции, позволяющие выгрузить в XML целую таблицу, или результат запроса, или даже всю базу данных в фиксированном формате.'

s 1 "SELECT table_to_xml(
    tbl => 'disks',
    nulls => true,        -- выводить столбцы с NULL
    tableforest => false, -- в корне один элемент <disks>
    targetns => ''        -- пространство имен XML не нужно
);"

P 11

###############################################################################
h 'JSON: типы данных json и jsonb'

c 'Документ, описывающий компоненты компьютера, может выглядеть в JSON так:'

s 1 'SELECT $js$
{ "motherboard": {
    "cpu": "Intel® Core™ i7-7567U",
    "ram": [
      { "type": "dimm",
        "size_gb": 32,
        "model": "Crucial DDR4-2400 SODIMM"
      }
    ]
  },
  "disks": [
    { "type": "ssd",
      "size_gb": 512,
      "model": "Intel 760p Series"
    },
    { "type": "hdd",
      "size_gb": 3000,
      "model": "Toshiba Canvio"
    }
  ]
}
$js$ AS json \gset'

c 'Формат json хранит документ как обычный текст:'

s 1 "SELECT :'json'::json;"

c 'В jsonb документ разбирается и записывается во внутреннем формате, сохраняющем структуру разбора. Из-за этого при выводе документ составляется заново в эквивалентном, но ином виде:'

s 1 "SELECT :'json'::jsonb \gx"

c 'Чтобы вывести документ в человекочитаемом виде, можно использовать специальную функцию:'

s 1 "SELECT jsonb_pretty(:'json'::jsonb);"

c 'Дальше мы будем работать с типом jsonb, который предоставляет больше возможностей.'

p

###############################################################################
h 'JSON: выражения JSONPath и другие средства'

c 'Для получения части JSON-документа стандарт SQL:2016 определил язык запросов JSONPath. Вот некоторые примеры.'

c 'Так же, как и XPath, JSONPath позволяет спускаться по дереву элементов. Часть документа, соответствующая пути от корня:'

s 1 "SELECT jsonb_pretty(jsonb_path_query(:'json', '$.motherboard.ram'));"

c 'Элементы массива указываются в квадратных скобках:'

s 1 "SELECT jsonb_pretty(jsonb_path_query(:'json', '$.disks[0]'));"

c 'Можно получить и все элементы сразу:'

s 1 "SELECT jsonb_pretty(jsonb_path_query(:'json', '$.disks[*]'));"

c 'Условия фильтрации записываются в скобках после вопросительного знака. Символ @ обозначает текущий путь.'
c 'Найдем диски, объем памяти которых начинается от 1000 гигабайт:'

s 1 "SELECT jsonb_pretty(
    jsonb_path_query(:'json', '$.disks ? (@.size_gb > 1000)')
);"

c 'Условия являются частью пути, который можно продолжить дальше. Выберем только модель:'

s 1 "SELECT jsonb_pretty(
    jsonb_path_query(:'json', '$.disks ? (@.size_gb > 1000).model')
);"

c 'В пути может быть и несколько условий:'

s 1 "SELECT jsonb_pretty(
    jsonb_path_query(
        :'json',
        '$.disks ? (@.size_gb > 128).model ? (@ starts with \"Intel\")'
    )
);"

p

c 'Кроме средств JSONPath, можно применять и «традиционную» стрелочную нотацию.'

c 'Переходим к ключу motherboard, затем к ключу ram, затем берем первый (нулевой) элемент массива:'

s 1 "SELECT jsonb_pretty( (:'json'::jsonb)->'motherboard'->'ram'->0 );"

c 'Двойная стрелка возвращает не jsonb, а текстовое представление (необходимые фильтрации придется выполнять уже на уровне SQL):'

s 1 "SELECT (:'json'::jsonb)->'motherboard'->'ram'->0->>'model';"

c 'Начиная с версии PostgreSQL 14 для работы c jsonb можно использовать индексную нотацию:'

s 1 "SELECT (:'json'::jsonb)['disks'][1]['model'];"

p

###############################################################################
h 'JSON: преобразование в реляционный вид и обратно'

c 'Стандарт определяет функцию jsontable, но ее реализация ожидается только в PostgreSQL 17. Разумеется, можно выйти из положения и теми средствами, которые существуют. Сначала выделим все диски:'

s 1 "TRUNCATE TABLE disks;"

s 1 "WITH dsk(d) AS (
    SELECT jsonb_path_query(:'json', '$.disks[*]')
)
SELECT d FROM dsk;"

c 'На основе этого запроса несложно сделать вставку в таблицу:'

s 1 "INSERT INTO disks(drive_type, name, capacity)
WITH dsk(d) AS (
    SELECT jsonb_path_query(:'json', '$.disks[*]')
)
SELECT d->>'type', d->>'model', (d->>'size_gb')::integer FROM dsk;"

p

c 'Для обратного преобразования удобно воспользоваться функцией row_to_json:'

s 1 "SELECT row_to_json(disks) FROM disks;"

c 'Соединить строки в общий JSON-массив  можно, например, так:'

s 1 "SELECT json_agg(disks) FROM disks;"

c 'Здесь отдельные строки преобразуются в объекты JSON автоматически.'

P 13

###############################################################################
h 'Метод доступа GIN для индексирования JSON'

c 'Пусть теперь таблица с дисками будет содержать JSON-документы.'

s 1 "DROP TABLE disks;"
s 1 "CREATE TABLE disks(
    id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    disk jsonb
);"

c 'Заполним ее разными моделями, от 10 до 1000 Гбайт:'

s 1 "INSERT INTO disks(disk)
WITH rnd(r) AS (
    SELECT (10+random()*990)::integer FROM generate_series(1,100_000)
),
dsk(type, model, capacity, plates) AS (
    SELECT 'hdd', 'NoName '||r||' GB', r, (1 + random()*9)::integer
    FROM rnd
)
SELECT row_to_json(dsk) FROM dsk;"

s 1 "ANALYZE disks;"

c 'Вот что получилось:'

s 1 "SELECT * FROM disks LIMIT 3;"

c 'Сколько всего моделей имеют емкость 10 Гбайт и сколько времени займет поиск?'

s 1 '\timing on'

c 'Оператор @? проверяет, есть ли в документе JSON заданный путь.'

s 1 "SELECT count(*) FROM disks WHERE disk @? '$ ? (@.capacity == 10)';"
s 1 '\timing off'

c 'Как выполняется этот запрос?'

s 1 "EXPLAIN (costs off)
SELECT count(*) FROM disks WHERE disk @? '$ ? (@.capacity == 10)';"

c 'Конечно, используется полное сканирование таблицы — у нас нет подходящего индекса.'

c 'Документы JSONB можно индексировать с помощью метода GIN. Для этого есть два доступных класса операторов:'

s 1 "SELECT opcname, opcdefault
FROM pg_opclass
WHERE opcmethod = (SELECT oid FROM pg_am WHERE amname = 'gin')
AND opcintype = 'jsonb'::regtype;"

c 'Класс по умолчанию, jsonb_ops, более универсален, но менее эффективен. Этот класс операторов помещает в индекс все ключи и значения. Из-за этого поиск получается неточным: значение 10 может быть найдено не только в контексте емкости (ключ capacity), но и как число пластин (ключ plates). Зато такой индекс поддерживает и другие операции с JSONB.'

c 'Попробуем.'

s 1 "CREATE INDEX disks_json_idx ON disks USING gin(disk);"

s 1 '\timing on'
s 1 "SELECT count(*) FROM disks WHERE disk @? '$ ? (@.capacity == 10)';"
s 1 '\timing off'

c 'Доступ, тем не менее, ускоряется.'

s 1 "EXPLAIN (costs off)
SELECT count(*) FROM disks WHERE disk @? '$ ? (@.capacity == 10)';"

p

c 'Другой класс операторов, jsonb_path_ops, помещает в индекс значения вместе с путем, который к ним ведет. За счет этого поиск становится более точным, хотя поддерживаются не все операции.'

c 'Проверим и этот способ:'

s 1 "CREATE INDEX disks_json_path_idx
ON disks USING gin(disk jsonb_path_ops);"

s 1 '\timing on'
s 1 "SELECT count(*) FROM disks WHERE disk @? '$ ? (@.capacity == 10)';"
s 1 '\timing off'

c 'Так гораздо лучше.'

c 'Еще один вариант — построить индекс на основе B-дерева по выражению. Вот так:'

s 1 "CREATE INDEX disks_btree_idx ON disks( (disk->>'capacity') );"

s 1 '\timing on'
s 1 "SELECT count(*) FROM disks WHERE disk->>'capacity' = '10';"
s 1 '\timing off'

c 'Но такой способ, конечно, менее универсален — под каждый запрос потребуется создавать отдельный индекс.'

c 'Сравним размер индексов (для сравнения выводится и размер таблицы):'

s 1 "SELECT indexname,
    pg_size_pretty(pg_total_relation_size(indexname::regclass))
FROM pg_indexes
WHERE tablename = 'disks'
UNION ALL
SELECT 'disks', pg_size_pretty(pg_table_size('disks'::regclass));"

###############################################################################

stop_here
cleanup
demo_end
