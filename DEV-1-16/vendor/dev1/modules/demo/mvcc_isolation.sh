#!/bin/bash

. ../lib

init

start_here 6

###############################################################################
h 'Управление уровнем изоляции'

c 'Для демонстрации мы будем использовать отдельную базу данных для каждой темы.'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c "Уровни изоляции посмотрим на примере с таблицей, представляющей состояние светофора:"

s 1 'CREATE TABLE lights(
  id integer GENERATED ALWAYS AS IDENTITY,
  lamp text,
  state text
);'

c "Это будет пешеходный светофор с двумя лампочками:"
s 1 "INSERT INTO lights(lamp,state) VALUES
    ('red', 'on'), ('green', 'off');"
s 1 'SELECT * FROM lights ORDER BY id;'

c 'Один способ установить уровень изоляции — команда SET TRANSACTION, выполненная в начале транзакции:'

s 1 'BEGIN;'
s 1 'SET TRANSACTION ISOLATION LEVEL READ COMMITTED;'

c 'Проверить текущий уровень можно, посмотрев значение параметра:'

s 1 'SHOW transaction_isolation;'
s 1 "COMMIT;"

c 'А можно указать уровень прямо в команде BEGIN:'

s 1 'BEGIN ISOLATION LEVEL READ COMMITTED;'
s 1 "COMMIT;"

c 'По умолчанию используется уровень Read Committed:'

s 1 'SHOW default_transaction_isolation;'

c 'Так что если этот параметр не менялся, можно не указывать уровень явно.'

s 1 'BEGIN;'
s 1 'SHOW transaction_isolation;'
s 1 "COMMIT;"

p

###############################################################################
h 'Read Committed и грязное чтение'

c 'Попробуем прочитать «грязные» данные. В первой транзакции гасим красный свет:'

s 1 'BEGIN;'
s 1 "UPDATE lights SET state = 'off' WHERE lamp = 'red';"

c 'Начнем второй сеанс.'

psql_open A 2 $TOPIC_DB

c 'В нем откроем еще одну транзакцию с тем же уровнем Read Committed.'

s 2 'BEGIN;'
s 2 'SELECT * FROM lights ORDER BY id;'

c 'Вторая транзакция не видит незафиксированных изменений.'

c 'Отменим изменение.'

s 1 'ROLLBACK;'
s 2 'ROLLBACK;'

p

###############################################################################
h 'Read Committed и чтение зафиксированных изменений'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | on
#   2 | green | off

c 'Мы проверили, что транзакция не видит незафиксированных изменений. Посмотрим, что будет при фиксации.'

s 1 'BEGIN;'
s 1 "UPDATE lights SET state = 'off' WHERE lamp = 'red';"

s 2 'BEGIN;'
s 2 'SELECT * FROM lights ORDER BY id;'

c 'Пока не видно.'

s 1 'COMMIT;'

c 'А теперь?'

s 2 'SELECT * FROM lights ORDER BY id;'
s 2 'COMMIT;'

c 'Итак, в режиме Read Committed операторы одной транзакции видят зафиксированные изменения других транзакций.'
c 'Заметьте, что при этом один и тот же запрос в одной и той же транзакции может выдавать разные результаты.'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | off
#   2 | green | off

p

c 'Можно ли увидеть изменения, зафиксированные в процессе выполнения одного оператора? Проверим.'

c 'Сейчас все лампочки погашены. Запустим долгий запрос и, пока он работает, включим свет во втором сеансе:'

ss 1 'SELECT *, pg_sleep(2) FROM lights ORDER BY id;'

sleep 1

was_interactive=$interactive
interactive=false
s 2 "UPDATE lights SET state = 'on';"
interactive=$was_interactive

r 1

c 'Итак, если во время выполнения оператора другая транзакция успела зафиксировать изменения, то они не будут видны. Оператор видит данные в таком состоянии, в котором они находились на момент начала его выполнения.'

p

c 'Однако если в запросе вызывается функция с категорией изменчивости volatile, выполняющая собственный запрос, то такой запрос внутри функции будет возвращать данные, не согласованные с данными основного запроса.'

s 1 "CREATE FUNCTION get_state(lamp text)
RETURNS text
LANGUAGE sql VOLATILE
RETURN (SELECT l.state FROM lights l WHERE l.lamp = get_state.lamp);"

c 'Повторим эксперимент, но теперь запрос будет использовать функцию:'

ss 1 'SELECT *, get_state(lamp), pg_sleep(2) FROM lights ORDER BY id;'

sleep 1

was_interactive=$interactive
interactive=false
s 2 "UPDATE lights SET state = 'off';"
interactive=$was_interactive

r 1

c 'Правильный вариант — объявить функцию с категорией изменчивости stable.'

s 1 "ALTER FUNCTION get_state STABLE;"

ss 1 'SELECT *, get_state(lamp), pg_sleep(2) FROM lights ORDER BY id;'

sleep 1

was_interactive=$interactive
interactive=false
s 2 "UPDATE lights SET state = 'on';"
interactive=$was_interactive

r 1

c 'Вывод: внимательно следите за категорией изменчивости функций на уровне изоляции Read Committed. Со значениями «по умолчанию» легко получить несогласованные данные.'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | on
#   2 | green | on

p

###############################################################################
h 'Read Committed и потерянные изменения'

c 'Что происходит при попытке изменения одной и той же строки двумя транзакциями? Сейчас все лампочки включены.'

s 1 'BEGIN;'
s 1 "UPDATE lights SET state = 'off' WHERE lamp = 'red';"

s 2 'BEGIN;'
ss 2 "UPDATE lights
SET state = CASE WHEN state = 'on' THEN 'off' ELSE 'on' END
WHERE lamp = 'red';"

sleep 1

c 'Вторая транзакция ждет завершения первой.'

s 1 'COMMIT;';

r 2;
s 2 'COMMIT;'

c 'Но какой будет результат? Вторая транзакция «щелкает переключателем», и результат зависит от значения, от которого она будет отталкиваться.'

s 1 'SELECT * FROM lights ORDER BY id;'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | on
#   2 | green | on

c 'С одной стороны, команда во второй транзакции не должна видеть изменений, сделанных после начала ее выполнения. Но с другой — она не должна потерять изменения, зафиксированные другими транзакциями. Поэтому после снятия блокировки она перечитывает строку, которую пытается обновить.'

c 'В итоге, первая транзакция выключает свет, а вторая снова включает его.'

c "Такой результат интуитивно кажется правильным, но достигается он за счет того, что транзакция может увидеть несогласованные данные: часть — на один момент времени, часть — на другой."

p

c 'Но если изменение выполняется не в одной команде SQL, то обновление будет потеряно. Повторим тот же пример.'

s 1 'BEGIN;'
s 1 "UPDATE lights SET state = 'off' WHERE lamp = 'red';"

s 2 'BEGIN;'

c 'Сначала читаем значение и запоминаем его на клиенте:'

s 2 "SELECT state AS old_state FROM lights WHERE lamp = 'red' \gset"
s 2 "\echo :old_state"

c 'А затем обновляем на сервере:'

ss 2 "UPDATE lights
SET state = CASE WHEN :'old_state' = 'on' THEN 'off' ELSE 'on' END
WHERE lamp = 'red';"

sleep 1

c 'Вторая транзакция ждет завершения первой.'

s 1 'COMMIT;';

r 2;
s 2 'COMMIT;'

c 'Какой результат будет на этот раз?'

s 1 'SELECT * FROM lights ORDER BY id;'

c 'В этом случае вторая транзакция перезаписала свои изменения «поверх» изменений первой транзакции. На уровне Read Committed сервер не может это предотвратить, поскольку команда UPDATE фактически содержит предопределенную константу.'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | off
#   2 | green | on

P 8

###############################################################################
h 'Repeatable Read и неповторяющееся чтение'

c 'Убедимся в отсутствии аномалии неповторяющегося чтения.'

s 1 'BEGIN ISOLATION LEVEL REPEATABLE READ;'
s 1 "SELECT * FROM lights WHERE lamp = 'red';"

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | off
#   2 | green | on

s 2 "UPDATE lights SET state = 'on' WHERE lamp = 'red' RETURNING *;"

c 'Какое значение получит первая транзакция?'

s 1 "SELECT * FROM lights WHERE lamp = 'red';"

c 'Повторное чтение измененной строки возвращает первоначальное значение.'

s 1 "COMMIT;"

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | on
#   2 | green | on

p

###############################################################################
h 'Repeatable Read и фантомное чтение'

c 'Фантомные записи также не должны быть видны. Проверим это.'

s 1 'BEGIN ISOLATION LEVEL REPEATABLE READ;'
s 1 "SELECT * FROM lights WHERE state = 'off';"

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | on
#   2 | green | on

s 2 "INSERT INTO lights(lamp,state) VALUES ('yellow', 'off') 
    RETURNING *;"

s 1 "SELECT * FROM lights WHERE state = 'off';"

c 'Действительно, транзакция не видит добавленной записи, удовлетворяющей первоначальному условию. Уровень изоляции Repeatable Read в PostgreSQL более строгий, чем того требует стандарт SQL.'

s 1 "COMMIT;"

c 'Уберем желтую лампочку.'

s 1 "DELETE FROM lights WHERE lamp = 'yellow';"

p

###############################################################################
h 'Repeatable Read и потерянные изменения'

c 'Необходимость все время видеть ровно те же данные, что и в самом начале, не позволяет перечитывать измененную строку в случае обновления.'
c 'Воспроизведем тот же пример, который мы видели на уровне изоляции Read Committed. Сейчас все лампочки включены.'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | on
#   2 | green | on

s 1 'BEGIN ISOLATION LEVEL REPEATABLE READ;'
s 1 "UPDATE lights SET state = 'off' WHERE lamp = 'red';"

s 2 'BEGIN ISOLATION LEVEL REPEATABLE READ;'
s 2 "SELECT state AS old_state FROM lights WHERE lamp = 'red' \gset"
s 2 "\echo :old_state"
ss 2 "UPDATE lights
SET state = CASE WHEN :'old_state' = 'on' THEN 'off' ELSE 'on' END
WHERE lamp = 'red';"

sleep 1

c 'Вторая транзакция ждет завершения первой.'

s 1 'COMMIT;';
r 2;

c "Во второй транзакции получаем ошибку. Строка была изменена; обновить неактуальную версию невозможно (это будет потерянным изменением, что недопустимо), а увидеть актуальную версию тоже невозможно (это нарушило бы изоляцию)."

s 2 'ROLLBACK;'

c 'Таким образом, потерянное обновление на уровне Repeatable Read не допускается.'

p

###############################################################################
h 'Repeatable Read и другие аномалии'

c "Можно ли быть уверенным в том, что следующая команда включит все лампочки?"

s_fake 1 "UPDATE lights SET state = 'on' WHERE state = 'off';"

c "Можно ли быть уверенным в том, что следующая команда выключит все лампочки?"

s_fake 1 "UPDATE lights SET state = 'off' WHERE state = 'on';"

c "Если одна транзакция включает лампочки, а другая — выключает, в каком состоянии останется таблица после одновременного выполнения двух этих транзакций?"

c 'Проверим. Начальное состояние:'

s 1 'SELECT * FROM lights ORDER BY id;'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | off
#   2 | green | on

s 1 'BEGIN ISOLATION LEVEL REPEATABLE READ;'
s 1 "UPDATE lights SET state = 'on' WHERE state = 'off';"

c 'Первая транзакция включила красную лампочку, и теперь все огни горят.'

s 1 'SELECT * FROM lights ORDER BY id;'

s 2 'BEGIN ISOLATION LEVEL REPEATABLE READ;'

c 'Вторая транзакция не видит этих, еще не зафиксированных, изменений и считает, что красный свет выключен. Поэтому она выключает зеленый и для нее все огни погашены.'

s 2 "UPDATE lights SET state = 'off' WHERE state = 'on';"
s 2 'SELECT * FROM lights ORDER BY id;'

c 'Теперь обе транзакции фиксируют свои изменения...'

s 1 'COMMIT;'

s 2 'COMMIT;'

c 'И оказывается, что...'

s 1 'SELECT * FROM lights ORDER BY id;'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | on
#   2 | green | off

c '...одна лампочка включена, а другая — выключена.'
c 'Это пример аномалии конкурентного доступа — несогласованная запись (write skew), — которая возможна, даже если нет грязного, неповторяющегося и фантомного чтений.'

P 10

###############################################################################
h 'Serializable'

c 'На этом уровне транзакции могут положиться на то, что на их работу никто не повлияет.'

#  id | lamp  | state 
# ----+-------+-------
#   1 | red   | on
#   2 | green | off

s 1 'BEGIN ISOLATION LEVEL SERIALIZABLE;'
s 1 "UPDATE lights SET state = 'on' WHERE state = 'off';"

c 'Первая транзакция включила зеленую лампочку, все огни горят.'

s 1 'SELECT * FROM lights ORDER BY id;'

c 'Вторая транзакция не видит зафиксированных изменений: для нее красный свет еще горит, и она выключает его.'

s 2 'BEGIN ISOLATION LEVEL SERIALIZABLE;'
s 2 "UPDATE lights SET state = 'off' WHERE state = 'on';"
s 2 'SELECT * FROM lights ORDER BY id;'

c 'Теперь обе транзакции фиксируют свои изменения...'

s 1 'COMMIT;'
s 2 'COMMIT;'

c 'И вторая транзакция получает ошибку.'

c 'Действительно, при последовательном выполнении транзакций допустимо два результата:'
ul 'если сначала выполняется первая транзакция, а потом вторая, то все лампочки будут погашены;'
ul 'если сначала выполняется вторая транзакция, а потом первая, то все лампочки будут включены.'
c '«Промежуточный» вариант получить невозможно, поэтому выполнение одной из транзакций завершается ошибкой.'

c 'Важный момент: чтобы уровень Serializable работал корректно, на этом уровне должны работать все транзакции. Если смешивать транзакции разных уровней, фактически Serializable будет вести себя, как Repeatable Read.'

###############################################################################

stop_here
cleanup
demo_end
