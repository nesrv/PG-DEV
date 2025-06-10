#!/bin/bash

. ../lib

init

echo 'Готовим базу данных...'
psql -qc "CREATE DATABASE $TOPIC_DB;"
zcat ~/mail_messages.sql.gz | psql -qtdo /dev/null $TOPIC_DB

start_here 6

###############################################################################
h 'Язык запросов'

c 'Будем знакомиться с полнотекстовым поиском на примере базы сообщений из рассылки pgsql-hackers за 1997-2017 года.'
c 'Эта база уже загружена из резервной копии командой'

e_fake "zcat ~/mail_messages.sql.gz | psql -d $TOPIC_DB"

s 1 "\c $TOPIC_DB"

# чтобы индексы побыстрее создавались (слушателям не показываем)
onair_save=$onair
onair=false
s 1 "SET maintenance_work_mem = '256MB';"
onair=$onair_save

c 'База представлена одной таблицей:'

s 1 'SELECT id, parent_id, sent, subject, author, left(body_plain,400) body
FROM mail_messages LIMIT 1 \gx'

c 'Мы преимущественно будем смотреть на темы писем, потому что они достаточно короткие.'

c 'Общее количество записей:'

s 1 'SELECT count(*) FROM mail_messages;'

c 'Чтобы воспользоваться полнотекстовым поиском, документ надо привести к типу tsvector, а запрос — к типу tsquery. Простой пример, в котором поисковый запрос состоит из одного слова:'

s 1 "SELECT id, subject FROM mail_messages 
WHERE to_tsvector(subject) @@ to_tsquery('magical') 
ORDER BY id LIMIT 5;"

c 'Стоит обратить внимание, что найдены документы, содержащие разные формы слова magical, независимо от регистра букв. Позже мы узнаем, как это происходит.'

c 'Язык запросов позволяет использовать логические связки. Документы, содержащие magic и value:'

s 1 "SELECT id, subject FROM mail_messages 
WHERE to_tsvector(subject) @@ to_tsquery('magic & value') 
ORDER BY id LIMIT 5;"

c 'Документы, содержащие magic и value, но не time:'

s 1 "SELECT id, subject FROM mail_messages 
WHERE to_tsvector(subject) @@ to_tsquery('magic & value & !time') 
ORDER BY id LIMIT 5;"

c 'Документы, содержащие magic и либо value, либо constant:'

s 1 "SELECT id, subject FROM mail_messages 
WHERE to_tsvector(subject) @@ to_tsquery('magic & (value | constant)') 
ORDER BY id LIMIT 5;"

c 'Также доступен фразовый поиск, учитывающий порядок и близость позиций лексем. Например, для фразы «time value»:'

s 1 "SELECT id, subject FROM mail_messages 
WHERE to_tsvector(subject) @@ to_tsquery('time <-> value') 
ORDER BY id LIMIT 5;"

c 'Или та же фраза «time value», но между словами должно быть еще одно любое слово:'

s 1 "SELECT id, subject FROM mail_messages 
WHERE to_tsvector(subject) @@ to_tsquery('time <2> value') 
ORDER BY id LIMIT 5;"

c 'Имеется также функция, позволяющая получить поисковый запрос, не указывая логические связки, примерно как в веб-поиске. Например, такой запрос:'

s_fake 1 "to_tsquery('(time <-> value) & !magic')"

c 'эквивалентен следующему:'

s 1 "SELECT id, subject FROM mail_messages 
WHERE to_tsvector(subject) @@ websearch_to_tsquery('\"time value\" -magic') 
ORDER BY id LIMIT 5;"

p

c 'Как вывести результат, если поиск идет по большому документу? Запрос выдаст нам весь текст письма:'

s 1 "SELECT body_plain FROM mail_messages 
WHERE to_tsvector(body_plain) @@ to_tsquery('magic') 
ORDER BY id LIMIT 1;"

p

c 'Но можно воспользоваться функцией для форматирования результата, чтобы показать то место в документе, где обнаружено соответствие:'

s 1 "SELECT id, translate(
  ts_headline(body_plain,
              to_tsquery('magic'),
              'StartSel=*,StopSel=*,MinWords=8,MaxWords=10'),
  E'\n',
  ' '
) FROM mail_messages 
WHERE to_tsvector(body_plain) @@ to_tsquery('magic') 
ORDER BY id LIMIT 5;"

P 8

###############################################################################
h 'Анализатор'

c 'Единственный установленный анализатор называется default:'

s 1 '\dFp'

c 'Посмотрим, как он разбивает текст на фрагменты — с помощью служебной функции:'

s 1 "SELECT *
FROM ts_parse('default', 'The bells from the chapel went jingle-jangle');"

c 'На этом этапе слова остаются без изменений. Обратите внимание, что из одного слова может получиться несколько «пересекающихся» фрагментов.'

c 'Типы фрагментов, выделяемые анализатором, можно посмотреть так:'

s 1 '\dFp+'

P 11

###############################################################################
h 'Словари'

c 'Посмотрим, как работает стемминг. Функция вернет нам заменяющую слово «The» лексему, обратившись к указанному в первом параметре словарю:'

s 1 "SELECT ts_lexize('english_stem','The');"

c 'Это стоп-слово, оно исчезает.'

c 'Другой пример:'

s 1 "SELECT ts_lexize('english_stem','Bells');"

c 'Слово приведено к нижнему регистру и отброшено окончание «s» — таким образом, мы найдем документ, если будем искать «bell» или «bells».'
c 'А превратится ли слово «went» в «go»?'

s 1 "SELECT ts_lexize('english_stem','went');"

c 'Нет — стемминг не справится с формами слова, для этого нужен полноценный морфологический словарь.'

c 'Представим, что в нашем документе встречаются слова с диакритическими знаками. Обычный стемминг сохранит букву с умляутом, но с точки зрения поиска это может быть нежелательным:'

s 1 "SELECT ts_lexize('english_stem','Röntgen');"

c 'Воспользуемся расширением unaccent, чтобы избавиться от умляута.'

s 1 'CREATE EXTENSION unaccent;'
s 1 "SELECT ts_lexize('unaccent','Röntgen');"

P 13

###############################################################################
h 'Настройка конфигурации'

c 'Для каждого типа фрагментов настраивается цепочка словарей — такая настройка называется конфигурацией. Доступные конфигурации:'

s 1 '\dF'

c 'Одна из них выбирается в качестве конфигурации по умолчанию и используется, если явно не указать другую:'

s 1 'SHOW default_text_search_config;'

c 'Посмотрим на эту конфигурацию подробнее:'

s 1 '\dF+ english'

c 'Например, для слов (word) используется стемминг английского языка (english_stem).'

c 'Встроим в конфигурацию словарь, который при обработке английских слов устраняет диакритические знаки. Для этого зададим цепочку словарей для лексем типа «слово» (word):'

s 1 'ALTER TEXT SEARCH CONFIGURATION english
ALTER MAPPING FOR word WITH unaccent, english_stem;'

s 1 '\dF+ english'

c 'Unaccent — фильтрующий словарь, поэтому к полученной лексеме далее будет применен стемминг. Проверим:'

s 1 "SELECT to_tsvector('Wilhelm Röntgen');"

c 'Итак, во что же превращается исходный текст при преобразовании в tsvector?'

s 1 "SELECT to_tsvector('The bells from the chapel went jingle-jangle');"

c 'Конечный результат — список лексем и их позиций в документе.'

c 'Аналогичное преобразование проходит и поисковый запрос:'

s 1 "SELECT to_tsquery('Jingle & bells');"

P 15

###############################################################################
h 'Производительность текстового поиска'

c 'Вернемся к примеру с архивом почтовых рассылок. Как мы видели, поиск может выполняться довольно долго, даже если искать по темам писем:'

s 1 '\timing on'
s 1 "SELECT count(*) FROM mail_messages 
WHERE to_tsvector(subject) @@ to_tsquery('magic');"
s 1 '\timing off'

c 'Что можно сделать? Во-первых, необходимо избавиться от преобразования документов в tsvector каждый раз, когда требуется что-то найти.'
c 'Добавим в таблицу столбец типа tsvector и заполним его. Учтем сразу и тему письма, и текст. У вектора поиска есть ограничение на размер слова, поэтому слишком длинные последовательности символов игнорируются.'

c 'Благодаря конструкции GENERATED ALWAYS, значения в столбце будут автоматически вычисляться для новых и измененных строк. Единственное ограничение: выражение должно иметь категорию изменчивости IMMUTABLE. Другой традиционный способ — обновлять значение с помощью триггера.'
c 'Создание отдельного столбца для tsvector — наиболее эффективное решение. Единственный минус состоит в том, что требуется дополнительное место для хранения tsvector.'
c 'Вместо создания столбца можно было бы сразу построить индекс по соответствующему выражению. В этом случае места нужно меньше, но эффективность поиска может страдать из-за необходимости повторных вычислений tsvector по документу.'

si 1 "ALTER TABLE mail_messages
ADD search_vector tsvector GENERATED ALWAYS AS (
    to_tsvector('english',subject) || to_tsvector('english',body_plain)
) STORED;"

c 'Теперь в запросе можно использовать уже готовое поле, но, конечно, будет по-прежнему просматриваться вся таблица:'

s 1 "EXPLAIN (costs off)
SELECT count(*) FROM mail_messages 
WHERE search_vector @@ to_tsquery('magic');"

c 'Поэтому следующий шаг к ускорению поиска — индексная поддержка.'
p

c 'Мы создадим индекс типа GIN. Это обычный выбор для полнотекстового поиска: индекс имеет сравнительно небольшой размер и обеспечивает более высокую точность поиска, чем GiST.'

si 1 "CREATE INDEX ON mail_messages USING gin(search_vector);"

s 1 "EXPLAIN (costs off)
SELECT count(*) FROM mail_messages 
WHERE search_vector @@ to_tsquery('magic');"

s 1 '\timing on'
s 1 "SELECT count(*) FROM mail_messages 
WHERE search_vector @@ to_tsquery('magic');"
s 1 '\timing off'

c 'Как видно, поиск теперь использует индекс и выполняется гораздо быстрее.'

c 'Вряд ли нам нужны все несколько тысяч результатов. Допустим, мы хотим получить десять наиболее релевантных.'

s 1 "EXPLAIN (costs off)
SELECT id, subject, ts_rank(search_vector, to_tsquery('magic')) rank
FROM mail_messages
WHERE search_vector @@ to_tsquery('magic')
ORDER BY rank DESC LIMIT 10;"

c 'Сначала находятся все результаты, ранжируются, сортируются, и только потом отбираются 10 лучших. Конечно, это неэффективно.'

c 'Такие запросы можно ускорить с помощью RUM-индекса.'

s 1 'CREATE EXTENSION rum;'

c 'Индекс типа RUM устроен так же, как GIN, но дополнительно хранит информацию о позициях лексем. Это позволяет вычислять релевантность (степень соответствия документа поисковому запросу) непосредственно при обходе индекса.'

si 1 "CREATE INDEX ON mail_messages USING rum(search_vector);"

c 'Вот как выглядит запрос, использующий упорядочивающий оператор <=>:'

s 1 "EXPLAIN (costs off)
SELECT id, subject, search_vector <=> to_tsquery('magic') distance
FROM mail_messages
WHERE search_vector @@ to_tsquery('magic')
ORDER BY search_vector <=> to_tsquery('magic')
LIMIT 10;"

s 1 '\timing on'
s 1 "SELECT id, subject, search_vector <=> to_tsquery('magic') distance
FROM mail_messages
WHERE search_vector @@ to_tsquery('magic')
ORDER BY search_vector <=> to_tsquery('magic')
LIMIT 10;"
s 1 '\timing off'

###############################################################################

stop_here
cleanup
demo_end
