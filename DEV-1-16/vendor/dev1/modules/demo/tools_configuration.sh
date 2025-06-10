#!/bin/bash


. ../lib

init

# Запомним полное имя конфиг.файла
conff=$(s_bare 1 "SHOW config_file;")
# Имя каталога include_dir
confd=$(dirname $conff)
confd=${confd}/$(grep include_dir ${conff} | sed 's/#.*$//' | grep -Eo "'[[:alpha:].]+'" | tr -d "'")

# Пока скрываем, тк не было темы о БД.
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

start_here 5

###############################################################################
h 'Файл postgresql.conf и представление pg_file_settings'

c 'Имя конфигурационного файла содержится в доступном для чтения параметре config_file. Имя конфигурационного файла можно указать с помощью ключа командной строки при запуске postgres.'
s 1 "SHOW config_file;"

c 'Посмотрим небольшой фрагмент конфигурационного файла.'

# Раздел FILE LOCATIONS

# Стартовая позиция и кол-во символов для вывода. Фрагмент конфигурационного файла для демонстрации.
vstartpos=$(grep -b -B1 '^# FILE LOCATIONS' $conff | head -1 | cut -d '-' -f1)
vlngth=$(grep -b -B2 '^# CONNECTIONS AND AUTHENTICATION' $conff | head -1 | cut -d '-' -f1) 
vlngth=$((vlngth-vstartpos))

# Если при \g в вывод попадает пустая строка, то после \g вывод команд s смещается на одну команду!
s 1 "SELECT pg_read_file('$conff', ${vstartpos}, ${vlngth}) \g (tuples_only=on format=unaligned)" conf

c 'К основному конфигурационному файлу postgresql.conf можно подключать дополнительные файлы конфигурации. Директивы подключения:'
ul 'include_dir — каталог с дополнительными файлами конфигурации;'
ul 'include — включает дополнительный файл конфигурации;'
ul 'include_if_exists — включает дополнительный файл конфигурации, если он существует.'
c 'Обычно эти директивы располагаются в завершающей части файла postgresql.conf:'

e "sudo grep -A3 ^include $conff" conf

c 'Чтобы увидеть настройки в конфигурационных файлах, можно обратиться к представлению pg_file_settings:'

s 1 "SELECT sourceline, name, setting, applied, error FROM pg_file_settings;"

c 'Представление выводит незакомментированные строки конфигурационных файлов. Столбец applied показывает, будет ли заданное значение применено при перечитывании. В частности, в столбце будет false, если:'
ul 'изменение требует рестарта сервера;'
ul 'существует строка с тем же параметром, которая будет прочитана позже;'
ul 'в одной из строк, где задается параметр, есть ошибка.'
c 'Представление также показывает имя файла конфигурации и номер строки, что удобно для поиска ошибок.'

p

###############################################################################
h 'Представление pg_settings'

c 'Возьмем для примера параметр work_mem. Он определяет объем памяти, выделяемый для таких операций, как сортировка или хеш-соединение. Не для всех запросов значения по умолчанию может быть достаточно. Подробнее о параметре work_mem можно узнать в курсе QPT «Оптимизация запросов».'

c 'Действующие значения всех параметров доступны в представлении pg_settings. Вот что в нем содержится для параметра work_mem:'

s 1 "SELECT name, unit, setting, boot_val, reset_val,
  source, sourcefile, sourceline, pending_restart, context
FROM pg_settings
WHERE name = 'work_mem' \gx"

c 'Рассмотрим ключевые столбцы представления pg_settings:'
ul 'name, unit — название и единица измерения параметра;'
ul 'setting — текущее значение;'
ul 'boot_val — значение по умолчанию;'
ul 'reset_val — начальное значение для сеансов;'
ul 'source — источник текущего значения параметра;'
ul 'sourcefile, sourceline  — файл конфигурации и номер строки, если текущее значение было задано в файле;'
ul 'pending_restart — true, если значение изменено в файле конфигурации, но для применения требуется перезапуск сервера.'

c 'Столбец context определяет действия, необходимые для применения параметра. Среди возможных значений:'
ul 'internal — изменить нельзя, значение задано при установке;'
ul 'postmaster — требуется перезапуск сервера;'
ul 'sighup — требуется перечитать файлы конфигурации,'
ul 'superuser — суперпользователь может изменить для своего сеанса;'
ul 'user — любой пользователь может изменить для своего сеанса.'

p

###############################################################################
h 'Порядок применения строк'

c 'При перечитывании конфигурации сначала читается основной файл, а затем дополнительные. Если один и тот же параметр встречается несколько раз, то устанавливается значение из последней считанной строки.'
c 'Например, укажем дважды параметр work_mem в дополнительном файле конфигурации:'
e "echo work_mem=12MB | sudo tee $confd/work_mem.conf" conf
e "echo work_mem=8MB | sudo tee -a $confd/work_mem.conf" conf

c "Содержимое файла $confd/work_mem.conf:"
s 1 "SELECT sourcefile, sourceline, name, setting, applied
FROM pg_file_settings WHERE sourcefile LIKE '%/work_mem.conf';"

c 'Значение applied = f для первой строки показывает, что она не будет применена.'
p

c 'Для параметра work_mem поле context имеет значение user. Значит, параметр можно менять прямо во время сеанса, и позже мы увидим, как это сделать.'
c 'А чтобы изменить значение во всех сеансах, достаточно перечитать файлы конфигурации:'

s 1 'SELECT pg_reload_conf();'

c 'Убедимся, что параметр work_mem получил значение из второй строки:'

s 1 "SELECT name, unit, setting, boot_val, reset_val,
  source, sourcefile, sourceline, pending_restart, context
FROM pg_settings
WHERE name = 'work_mem'\gx"

P 7

###############################################################################
h 'Команда ALTER SYSTEM и файл postgresql.auto.conf'

# Сначала файл не показываем, потому что он появляется только после первого ALTER SYSTEM

c 'Для примера установим параметр work_mem:'

s 1 "ALTER SYSTEM SET work_mem TO '16mb';"

c 'Что случилось?'

p

c 'ALTER SYSTEM выполняет проверку на допустимые значения.'

s 1 "ALTER SYSTEM SET work_mem TO '16MB';"

c 'Вот теперь все правильно.'

p

c 'В результате выполнения команды значение 16MB записано в файл postgresql.auto.conf:'

s 1 "SELECT pg_read_file('postgresql.auto.conf')
\g (tuples_only=on format=unaligned)" conf

p

c 'Но это значение не применено:'

s 1 "SHOW work_mem;"

c 'Чтобы применить изменение work_mem, перечитаем файлы конфигурации:'

s 1 "SELECT pg_reload_conf();"
sleep-ni 1

s 1 "SELECT name, unit, setting, boot_val, reset_val,
  source, sourcefile, sourceline, pending_restart, context
FROM pg_settings
WHERE name = 'work_mem'\gx"

p

c 'Для удаления строк из postgresql.auto.conf используется команда ALTER SYSTEM RESET:'

s 1 "ALTER SYSTEM RESET work_mem;"
s 1 "SELECT pg_read_file('postgresql.auto.conf')
\g (tuples_only=on format=unaligned)" conf

p

c 'Еще раз перечитаем конфигурацию. Теперь восстановится значение из work_mem.conf:'

s 1 "SELECT pg_reload_conf();"
s 1 "SELECT name, unit, setting, boot_val, reset_val,
  source, sourcefile, sourceline, pending_restart, context
FROM pg_settings
WHERE name = 'work_mem'\gx"

P 9

###############################################################################
h 'Установка параметров для текущего сеанса'

#c 'Все последующие запросы будут возвращать одну строку, поэтому уберем лишний вывод.'
#s 1 '\pset footer off'

c 'Для изменения параметров во время сеанса можно использовать команду SET:'

s 1 "SET work_mem TO '24MB';"

c 'Или функцию set_config:'
s 1 "SELECT set_config('work_mem', '32MB', false);"

c 'Третий параметр функции говорит о том, нужно ли устанавливать значение только для текущей транзакции (true) или до конца работы сеанса (false). Это важно при работе приложения через пул соединений, когда в одном сеансе могут выполняться транзакции разных пользователей.'
p

###############################################################################
h 'Чтение значений параметров во время выполнения'

c 'Получить значение параметра можно разными способами:'

s 1 "SHOW work_mem;"
s 1 "\dconfig work_mem"
s 1 "SELECT current_setting('work_mem');"
s 1 "SELECT name, setting, unit FROM pg_settings WHERE name = 'work_mem';"

c 'Сбросим значение к тому, которое действовало в начале сеанса:'
s 1 "RESET work_mem;"

p

###############################################################################
h 'Установка параметров внутри транзакции'

c 'Откроем транзакцию и установим новое значение work_mem:'
s 1 "BEGIN;"
s 1 "SET work_mem TO '64MB';"
s 1 "SHOW work_mem;"

c 'Если транзакция откатывается, установка параметра отменяется, хотя при успешной фиксации новое значение продолжало бы действовать.'
s 1 "ROLLBACK;"
s 1 "SHOW work_mem;"

c 'Можно установить значение только до конца текущей транзакции:'
s 1 'BEGIN;'
s 1 "SET LOCAL work_mem TO '64MB'; -- или set_config('work_mem','64MB',true);"
s 1 "SHOW work_mem;"
s 1 "COMMIT;"

c 'По завершении транзакции значение восстанавливается:'
s 1 "SHOW work_mem;"

p

###############################################################################
h 'Пользовательские параметры'

c 'Параметры можно создавать прямо во время сеанса, в том числе с предварительной проверкой на существование.'
c 'В имени пользовательских параметров обязательно должна быть точка, чтобы отличать их от стандартных параметров.'

s 1 "SELECT CASE
  WHEN current_setting('myapp.currency_code', true) IS NULL
    THEN set_config('myapp.currency_code', 'RUB', false)
  ELSE
    current_setting('myapp.currency_code')
END;"

c 'Теперь myapp.currency_code можно использовать как глобальную переменную сеанса:'
s 1 "SELECT current_setting('myapp.currency_code');"

c 'Пользовательские параметры можно указывать и в конфигурационных файлах, тогда они автоматически будут инициализироваться во всех сеансах.'

###############################################################################
stop_here
cleanup 
demo_end
