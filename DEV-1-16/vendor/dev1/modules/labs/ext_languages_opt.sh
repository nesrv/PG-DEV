#!/bin/bash

. ../lib

init

start_here ...

###############################################################################
h '1. Количество вхождений слов в строку'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

s 1 "CREATE EXTENSION plpython3u;"

s 1 "CREATE FUNCTION words_count(s text)
RETURNS TABLE(word text, cnt integer)
AS \$python\$
    words = {}
    for w in s.split():
        words[w] = words.get(w,0) + 1
    return words.items()
\$python\$ LANGUAGE plpython3u IMMUTABLE;"

s 1 "SELECT * FROM words_count('раз два три два три три');"

c 'На SQL задача тоже решается элементарно. Здесь вместо явного использования ассоциативного массива мы полагаемся на реализацию группировки:'

s 1 "SELECT word, count(*)
FROM regexp_split_to_table('раз два три два три три','\s+') word
GROUP BY word;"

c 'Фактически в обоих случаях используется хеш-таблица:'

s 1 "EXPLAIN (costs off) SELECT word, count(*)
FROM regexp_split_to_table('раз два три два три три','\s+') word
GROUP BY word;"

###############################################################################
h '2. Тип файла'

s 1 "CREATE EXTENSION plsh;"

s 1 "CREATE FUNCTION file_type(file text) RETURNS text AS \$sh\$
#!/bin/bash
file --brief --mime-type \$1
\$sh\$ LANGUAGE plsh VOLATILE;"

s 1 "SELECT file_type('/home/$OSUSER/covers/novikov_dbtech2.jpg');"

###############################################################################

stop_here
cleanup
