#!/bin/bash

. ../lib

init

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

start_here 6

###############################################################################
h 'Анонимные блоки'

# TODO нет примера объявления переменной с NOT NULL

c 'Общая структура блока PL/pgSQL:'

s_fake 1 "<<метка>>
DECLARE
    -- объявления переменных
BEGIN
    -- операторы
EXCEPTION
    -- обработка ошибок
END метка;"

ul 'Все секции, кроме секции операторов, являются необязательными.'

p

c 'Минимальный блок PL/pgSQL-кода:'

s 1 "DO \$\$
BEGIN
    -- сами операторы могут и отсутствовать
END
\$\$;"

c 'Вариант программы Hello, World!'

s 1 "DO \$\$
DECLARE
    -- Это однострочный комментарий.
    /* А это — многострочный.
       После каждого объявления ставится знак ';'.
       Этот же знак ставится после каждого оператора.
    */
    foo text;
    bar text := 'World'; -- также допускается = или DEFAULT
BEGIN
    foo := 'Hello'; -- это присваивание
    RAISE NOTICE '%, %!', foo, bar; -- вывод сообщения
END
\$\$;"

ul 'После BEGIN точка с запятой не ставится!'

p

c 'Переменные могут иметь модификаторы:'
ul 'CONSTANT — значение переменной не должно изменяться после инициализации;'
ul 'NOT NULL — не допускается неопределенное значение.'

s 1 "DO \$\$
DECLARE
    foo integer NOT NULL := 0;
    bar CONSTANT text := 42;
BEGIN
    bar := bar + 1; -- ошибка
END
\$\$;"

p

c 'Пример вложенных блоков. Переменная во внутреннем блоке перекрывает переменную из внешнего блока, но с помощью меток можно обратиться к любой из них:'

s 1 "DO \$\$
<<outer_block>>
DECLARE
    foo text := 'Hello';
BEGIN
    <<inner_block>>
    DECLARE
        foo text := 'World';
    BEGIN
        RAISE NOTICE '%, %!', outer_block.foo, inner_block.foo;
        RAISE NOTICE 'Без метки — внутренняя переменная: %', foo;
    END inner_block;
END outer_block
\$\$;"

P 8

###############################################################################
h 'Подпрограммы PL/pgSQL'

c 'Пример функции, возвращающей значение с помощью оператора RETURN:'

s 1 "CREATE FUNCTION sqr_in(IN a numeric) RETURNS numeric
AS \$\$
BEGIN
    RETURN a * a;
END
\$\$ LANGUAGE plpgsql IMMUTABLE;"

c 'Та же функция, но с OUT-параметром. Возвращаемое значение присваивается параметру:'

s 1 "CREATE FUNCTION sqr_out(IN a numeric, OUT retval numeric)
AS \$\$
BEGIN
    retval := a * a;
END
\$\$ LANGUAGE plpgsql IMMUTABLE;"

c "Та же функция, но с INOUT-параметром. Такой параметр используется и для принятия входного значения, и для возврата значения функции:"

s 1 "CREATE FUNCTION sqr_inout(INOUT a numeric)
AS \$\$
BEGIN
    a := a * a;
END
\$\$ LANGUAGE plpgsql IMMUTABLE;"

s 1 "SELECT sqr_in(3), sqr_out(3), sqr_inout(3);"

P 10

###############################################################################
h 'Условные операторы'

c 'Общий вид оператора IF:'

s_fake 1 "IF условие THEN
    -- операторы
ELSIF условие THEN
    -- операторы
ELSE
    -- операторы
END IF;"

ul 'Секция ELSIF может повторяться несколько раз, а может отсутствовать.'
ul 'Секция ELSE может отсутствовать.'
ul 'Выполняются операторы, соответствующие первому истинному условию.'
ul 'Если ни одно из условий не истинно, выполняются операторы ELSE (если есть).'

p

c 'Пример функции, использующей условный оператор для форматирования номера телефона. Функция возвращает значение составного типа:'

s 1 "CREATE FUNCTION fmt (IN phone text, OUT code text, OUT num text)
AS \$\$
BEGIN
    IF phone ~ '^[0-9]*\$' AND length(phone) = 10 THEN
        code := substr(phone,1,3);
        num  := substr(phone,4);
    ELSE
        code := NULL;
        num  := NULL;
    END IF;
END
\$\$ LANGUAGE plpgsql IMMUTABLE;"

s 1 "SELECT fmt('8122128506');"

p

c 'Общий вид оператора CASE (первый вариант — по условию):'

s_fake 1 "CASE
    WHEN условие THEN
        -- операторы
    ELSE
        -- операторы
END CASE;"

ul 'Секция WHEN может повторяться несколько раз.'
ul 'Секция ELSE может отсутствовать.'
ul 'Выполняются операторы, соответствующие первому истинному условию.'
ul 'Если ни одно из условий не истинно, выполняются операторы ELSE (отсутствие ELSE в таком случае — ошибка).'

p

c 'Пример использования:'

s 1 "DO \$\$
DECLARE
    code text := (fmt('8122128506')).code;
BEGIN
    CASE
        WHEN code IN ('495','499') THEN
            RAISE NOTICE '% — Москва', code;
        WHEN code = '812' THEN
            RAISE NOTICE '% — Санкт-Петербург', code;
        WHEN code = '384' THEN
            RAISE NOTICE '% — Кемеровская область', code;
        ELSE
            RAISE NOTICE '% — Прочие', code;
    END CASE;
END
\$\$;"

p

c 'Общий вид оператора CASE (второй вариант — по выражению):'

s_fake 1 "CASE выражение
    WHEN значение, ... THEN
        -- операторы
    ELSE
        -- операторы
END CASE;"

ul 'Секция WHEN может повторяться несколько раз.'
ul 'Секция ELSE может отсутствовать.'
ul 'Выполняются операторы, соответствующие первому истинному условию «выражение = значение».'
ul 'Если ни одно из условий не истинно, выполняются операторы ELSE (отсутствие ELSE в таком случае — ошибка).'

p

c 'При однотипных условиях эта форма CASE может оказаться компактней:'

s 1 "DO \$\$
DECLARE
    code text := (fmt('8122128506')).code;
BEGIN
    CASE code
        WHEN '495', '499' THEN
            RAISE NOTICE '% — Москва', code;
        WHEN '812' THEN
            RAISE NOTICE '% — Санкт-Петербург', code;
        WHEN '384' THEN
            RAISE NOTICE '% — Кемеровская область', code;
        ELSE
            RAISE NOTICE '% — Прочие', code;
    END CASE;
END
\$\$;"

P 12

###############################################################################
h "Циклы"

# TODO нет примера CONTINUE

c "В PL/pgSQL все циклы используют общую конструкцию:"

s_fake 1 "LOOP
    -- операторы
END LOOP;"

c 'К ней может добавляться заголовок, определяющий условие выхода из цикла.'

p

c 'Цикл по диапазону FOR повторяется, пока счетчик цикла пробегает значения от нижней границы до верхней. С каждой итерацией счетчик увеличивается на 1 (но инкремент можно изменить в необязательной фразе BY).'

s_fake 1 "FOR имя IN низ .. верх BY инкремент
LOOP
    -- операторы
END LOOP;"

ul "Переменная, выступающая счетчиком цикла, объявляется неявно и существует только внутри блока LOOP — END LOOP."

p

c "При указании REVERSE значение счетчика на каждой итерации уменьшается, а нижнюю и верхнюю границы цикла нужно поменять местами:"

s_fake 1 "FOR имя IN REVERSE верх .. низ BY инкремент
LOOP
    -- операторы
END LOOP;"

p

c 'Пример использования цикла FOR — функция, "переворачивающая" строку:'

s 1 "CREATE FUNCTION reverse_for (line text) RETURNS text
AS \$\$
DECLARE
    line_length CONSTANT int := length(line);
    retval text := '';
BEGIN
    FOR i IN 1 .. line_length
    LOOP
        retval := substr(line, i, 1) || retval;
    END LOOP;
    RETURN retval;
END
\$\$ LANGUAGE plpgsql IMMUTABLE STRICT;"

c 'Напомним, что строгая (STRICT) функция немедленно возвращает NULL, если хотя бы один из входных параметров не определен. Тело функции при этом не выполняется.'

p

c "Цикл WHILE выполняется до тех пор, пока истинно условие:"

s_fake 1 "WHILE условие
LOOP
    -- операторы
END LOOP;"

p

c 'Та же функция, обращающая строку, с использованием цикла WHILE:'

s 1 "CREATE FUNCTION reverse_while (line text) RETURNS text
AS \$\$
DECLARE
    line_length CONSTANT int := length(line);
    i int := 1;
    retval text := '';
BEGIN
    WHILE i <= line_length
    LOOP
        retval := substr(line, i, 1) || retval;
        i := i + 1;
    END LOOP;
    RETURN retval;
END
\$\$ LANGUAGE plpgsql IMMUTABLE STRICT;"

p

c 'Цикл LOOP без заголовка выполняется бесконечно. Для выхода используется оператор EXIT:'

s_fake 1 "EXIT метка WHEN условие;"

ul 'Метка необязательна; если не указана, будет прерван самый вложенный цикл.'
ul 'Фраза WHEN также необязательна; при отсутствии цикл прерывается безусловно.'

p

c 'Пример использования цикла LOOP:'

s 1 "CREATE FUNCTION reverse_loop (line text) RETURNS text
AS \$\$
DECLARE
    line_length CONSTANT int := length(reverse_loop.line);
    i int := 1;
    retval text := '';
BEGIN
    <<main_loop>>
    LOOP
        EXIT main_loop WHEN i > line_length;
        retval := substr(reverse_loop.line, i,1) || retval;
        i := i + 1;
    END LOOP;
    RETURN retval;
END
\$\$ LANGUAGE plpgsql IMMUTABLE STRICT;"

ul 'Тело функции помещается в неявный блок, метка которого совпадает с именем функции. Поэтому к параметрам можно обращаться как «имя_функции.параметр».'

p

c "Убедимся, что все функции работают правильно:"

s 1 "SELECT reverse_for('главрыба') as \"for\",
          reverse_while('главрыба') as \"while\",
          reverse_loop('главрыба') as \"loop\";"

c "Замечание. В PostgreSQL есть встроенная функция reverse."

p

c 'Иногда бывает полезен оператор CONTINUE, начинающий новую итерацию цикла:'

s 1 "DO \$\$
DECLARE
    s integer := 0;
BEGIN
    FOR i IN 1 .. 100
    LOOP
        s := s + i;
        CONTINUE WHEN mod(i, 10) != 0;
        RAISE NOTICE 'i = %, s = %', i, s;
    END LOOP;
END
\$\$;"

P 14

###############################################################################
h 'Вычисление выражений'

c 'Выражения в PL/pgSQL выполняются SQL-движком. Таким образом, в PL/pgSQL доступно ровно то, что доступно в SQL. Например, если в SQL можно использовать конструкцию CASE, то точно такая же конструкция будет работать и в коде на PL/pgSQL (в качестве выражения; не путайте с оператором CASE ... END CASE, который есть только в PL/pgSQL):'

s 1 "DO \$\$
BEGIN
    RAISE NOTICE '%', CASE 2+2 WHEN 4 THEN 'Все в порядке' END;
END
\$\$;"

c 'В выражениях можно использовать и подзапросы:'

s 1 "DO \$\$
BEGIN
    RAISE NOTICE '%', (
        SELECT code
        FROM (VALUES (1, 'Раз'), (2, 'Два')) t(id, code)
        WHERE id = 1
    );
END
\$\$;"

c 'Еще пример с вычислением выражения в PL/pgSQL — сколько функций «обращения» строк у нас в результате получилось?'

s 1 "DO \$\$
DECLARE
  s integer;
BEGIN
  s := count(*) FROM pg_proc WHERE proname LIKE 'reverse%';
  RAISE NOTICE 'Всего функций \"reverse\" : %', s;
END
\$\$;"


###############################################################################

stop_here
cleanup
demo_end
