#!/bin/bash

. ../lib

init

start_here 5

###############################################################################
h 'Языки программирования'

s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Проверим список установленных языков:'

s 1 '\dL'

c 'По умолчанию установлен только PL/pgSQL (C и SQL не в счет).'

c 'Новые языки принято оформлять как расширения. Вот какие доступны для установки:'

s 1 "SELECT name, comment, installed_version
FROM pg_available_extensions
WHERE name LIKE 'pl%'
ORDER BY name;"

c 'Первые четыре — из числа стандартных, а с двумя последними мы познакомимся позже.'

c 'Установим в текущую базу данных два варианта языка PL/Perl: plperl (доверенный) и plperlu (недоверенный):'

s 1 'CREATE EXTENSION plperl;'
s 1 'CREATE EXTENSION plperlu;'
s 1 '\dL'

c 'Чтобы языки автоматически появлялись во всех новых базах данных, расширения нужно установить в БД template1.'

p

c 'Недоверенный язык не имеет ограничений. Например, можно создать функцию, читающую любой файл (аналогично штатной функции pg_read_file):'

s 1 'CREATE FUNCTION read_file_untrusted(fname text) RETURNS SETOF text
AS $perl$
    my ($fname) = @_;
    open FILE, $fname or die "Cannot open file";
    chomp(my @f = <FILE>);
    close FILE;
    return \@f;
$perl$ LANGUAGE plperlu VOLATILE;'

s 1 "SELECT * FROM read_file_untrusted('/etc/passwd') LIMIT 3;"

c 'Что будет, если попробовать сделать то же самое на доверенном языке?'

s 1 'CREATE FUNCTION read_file_trusted(fname text) RETURNS SETOF text
AS $perl$
    my ($fname) = @_;
    open FILE, $fname or die "Cannot open file";
    chomp(my @f = <FILE>);
    close FILE;
    return \@f;
$perl$ LANGUAGE plperl VOLATILE;'

c 'Вызов open (в числе прочего) запрещен в доверенном языке.'

P 7

###############################################################################
h 'Подключение нового языка'

c 'Если заглянуть, что выполняет команда CREATE EXTENSION, то для недоверенного языка в скрипте мы увидим примерно следующее:'

s_fake 1 "CREATE LANGUAGE plperlu
  HANDLER plperlu_call_handler
  INLINE plperlu_inline_handler
  VALIDATOR plperlu_validator;"

c 'А для доверенного (обратите внимание на слово TRUSTED):'

s_fake 1 "CREATE TRUSTED LANGUAGE plperl
  HANDLER plperl_call_handler
  INLINE plperl_inline_handler
  VALIDATOR plperl_validator;"

c 'В этой команде указываются имена функций, реализующих точки входа основного обработчика, обработчика для DO и проверки.'

p

c 'Установим еще один язык — PL/Python. Он доступен только как недоверенный:'

s 1 "CREATE EXTENSION plpython3u;"

c 'На его примере посмотрим, как происходит преобразование между системой типов SQL и системой типов языка. Для многих типов предусмотрены преобразования:'

s 1 "CREATE FUNCTION test_py_types(n numeric, b boolean, s text, a int[])
RETURNS void AS \$python\$
    plpy.info(n, type(n))
    plpy.info(b, type(b))
    plpy.info(s, type(s))
    plpy.info(a, type(a))
\$python\$ LANGUAGE plpython3u IMMUTABLE;"

s 1 "SELECT test_py_types(42,true,'foo',ARRAY[1,2,3]);"

c 'А что мы увидим в таком случае?'

s 1 "CREATE FUNCTION test_py_jsonb(j jsonb)
RETURNS jsonb AS \$python\$
    plpy.info(j, type(j))
    return j
\$python\$ LANGUAGE plpython3u IMMUTABLE;"

s 1 "SELECT test_py_jsonb('{ \"foo\": \"bar\" }'::jsonb);"

c 'Здесь SQL-тип json был передан в функцию как строка, а возвращаемое значение было вновь преобразовано в jsonb из текстового представления.'

h 'Трансформации типов'

c 'Чтобы помочь обработчику языка, можно создать дополнительные трансформации типов. Для нашего случая есть подходящее расширение:'

s 1 "CREATE EXTENSION jsonb_plpython3u;"

c 'Фактически оно создает трансформацию таким образом (что позволяет передавать тип jsonb и в Python, и обратно в SQL):'

s_fake 1 "CREATE TRANSFORM FOR jsonb LANGUAGE plpython3u (
    FROM SQL WITH FUNCTION jsonb_to_plpython3(internal),
    TO SQL WITH FUNCTION plpython3_to_jsonb(internal)
);"

c 'Трансформацию необходимо явно указать в определении функции:'

s 1 "CREATE OR REPLACE FUNCTION test_py_jsonb(j jsonb)
RETURNS jsonb
TRANSFORM FOR TYPE jsonb -- использовать трансформацию
AS \$python\$
    plpy.info(j, type(j))
    return j
\$python\$ LANGUAGE plpython3u IMMUTABLE;"

s 1 "SELECT test_py_jsonb('{ \"foo\": \"bar\" }'::jsonb);"

c 'Теперь SQL-тип jsonb передается в Python как тип dict — словарь (ассоциативный массив).'

P 9
###############################################################################
h 'Интерфейс SPI'

c 'Для доступа к возможностям SPI подпрограммы на языке Python автоматически импортируют модуль plpy (мы уже использовали функцию info из этого модуля — аналог команды RAISE INFO языка PL/pgSQL).'

s 1 "CREATE TABLE test(
    n integer PRIMARY KEY,
    descr text
);"
s 1 "INSERT INTO test VALUES (1,'foo'), (2,'bar'), (3,'baz');"

c 'Напишем для примера функцию, возвращающую текстовое описание по ключу. Отсутствие ключа должно приводить к ошибке.'
c 'Какие конструкции здесь соответствуют обращению к SPI?'

s 1 'CREATE FUNCTION get_descr_py(n integer) RETURNS text
AS $python$
    if "plan_get_descr_py" in SD:
        plan = SD["plan_get_descr_py"]
    else:
        plan = plpy.prepare(
            "SELECT descr FROM test WHERE n = $1", ["integer"]
        )
        SD["plan_get_descr_py"] = plan
    rows = plan.execute([n])
    if rows.nrows() == 0:
        raise plpy.spiexceptions.NoDataFound()
    else:
        return rows[0]["descr"]
$python$ LANGUAGE plpython3u STABLE;'

c 'Вызов plpy.prepare соответствует функции SPI_prepare (и SPI_keepplan), а plpy.execute — функции SPI_execute_plan. Также неявно вызывается SPI_connect и SPI_finish. То есть обертка языка может дополнительно упрощать интерфейс.'

c 'Обратите внимание:'
ul 'Чтобы сохранить план подготовленного запроса, приходится использовать словарь SD, сохраняемый между вызовами функции;'
ul 'Требуется явная проверка того, что строка была найдена.'

s 1 "SELECT get_descr_py(1);"
s 1 "SELECT get_descr_py(42);"

c 'Показательно сравнить с аналогичной функцией на языке PL/pgSQL:'

s 1 'CREATE FUNCTION get_descr(n integer) RETURNS text
AS $$
DECLARE
    descr text;
BEGIN
    SELECT t.descr INTO STRICT descr
    FROM test t WHERE t.n = get_descr.n;
    RETURN descr;
END;
$$ LANGUAGE plpgsql STABLE;'

ul 'План подготавливается и переиспользуется автоматически;'
ul 'Проверка существования строки указывается словом STRICT.'

s 1 "SELECT get_descr(1);"
s 1 "SELECT get_descr(42);"

c 'Другие языки могут предоставлять другой способ доступа к функциям SPI, а могут и не предоставлять.'

P 12

###############################################################################
h 'Пример специализированного языка: XSLT'

c 'В качестве иллюстрации очень специализированного языка (который никак нельзя назвать процедурным!) посмотрим на PL/XSLT. Допустим, мы получаем данные для отчета с помощью запроса, и представляем их в формате XML:'

s 1 "SELECT *
FROM query_to_xml('SELECT n, descr FROM test',true,false,'');"

c 'Чтобы вывести отчет пользователю, его можно преобразовать в формат HTML с помощью XSLT-преобразования. Подключим язык PL/XSLT:'

s 1 "CREATE EXTENSION plxslt;"

c 'Вот так может выглядеть простое преобразование:'

s 1 'CREATE FUNCTION html_report(xml) RETURNS xml
AS $xml$
<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:template match="/">
<html><body><table>
    <xsl:for-each select="table/row">
        <tr>
          <td><xsl:value-of select="n"/></td>
          <td><xsl:value-of select="descr"/></td>
        </tr>
    </xsl:for-each>
</table></body></html>
</xsl:template>
</xsl:stylesheet>
$xml$ LANGUAGE xslt IMMUTABLE;'

c 'И вот результат:'

s 1 "SELECT * FROM html_report(
    query_to_xml('SELECT * FROM test',true,false,'')
);"

c 'Таким образом можно разделить логику отчета (обычный SQL-запрос) и его представление.'

###############################################################################

stop_here
cleanup
demo_end

