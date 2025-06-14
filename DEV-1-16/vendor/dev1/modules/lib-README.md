# Назначение

Библиотека `lib` позволяет использовать shell-скрипты для демонстраций, беря на себя управление серверами PostgreSQL, выполнение команд psql в нескольких сеансах, подсветку синтаксиса и т. п. 

# Параметры

При запуске без параметров демонстрация выполняется в интерактивном режиме. Команды выводятся в терминал, значительная часть из них требует нажатия `Enter` для продолжения.

Параметр `--non-interactive` включает неинтерактивный режим, в котором команды выполняются без подтверждения нажатием `Enter`. Такой режим полезен для отладки, чтобы быстро выполнить демонстрацию.

Параметр `--html` включает вывод в формате HTML. Используется вместе с `--non-interactive` при генерации материалов скриптом `generate_handouts.sh`.

# Настройки курса в файле params

В sh-файле `params` задаются переменные уровня курса, а также определяются _серверы_ и _терминалы_.

*Переменные курса*:

```sh
COURSE          # имя курса
OSUSER=student  # имя пользователя в ОС
H               # путь к каталогу пользователя postgres
```

*Сервер* - это экземпляры PostgreSQL, которые используются в демонстрации. Сервер можно запустить, остановить и т. п. Сервер определяется идентификатором; обычно используется одна буква (A - основной сервер; R - реплика и т. п.).

Сервер может управляться `pg_ctlcluster` (если он установлен из пакета Ubuntu), `pg_ctl` (если собран из исходных кодов) или `systemctl` (для PostgresPro). Для каждого сервера, управляемого через `pg_ctlcluster`, должны быть определены следующие переменные (`A` заменить на идентификатор сервера):

```sh
export CONTROL_A=pg_ctlcluster
# номер основной версии
export VERSION_A=16
# имя кластера
export CLUSTER_A=main
# порт сервера, по умолчанию 5432
export PORT_A=5432
# расположение каталога PGDATA
export PGDATA_A='/var/lib/postgresql/16/main'
# расположение журнала сообщений
export LOG_A=/var/log/postgresql/postgresql-16-main.log
# путь к исполняемым файлам
export BINPATH_A='/usr/lib/postgresql/16/bin/'
```

Для каждого сервера, управляемого через `pg_ctl`, должны быть определены те же переменные, за исключением VERSION и CLUSTER.

Если сервер управляется посредством `systemctl`, то в переменной SERVICE_A предполагается имя службы systemctl, например, "postgrespro-ent-16.service". Остальные переменные такие же.

*Терминал* - это psql-сеанс, подключенный к одному из серверов. Он определяет стиль отображения команд. Терминал определяется порядковым номером.

Для каждого терминала могут быть определены следующие переменные (`1` заменить на номер терминала):

```sh
# Приглашение
export PSQL_PROMPT1='=> '
# Префикс (используется для отбивки команд)
export TABS1='    '
```

Приглашение меняется нечасто, но иногда удобно добавить в него, например, имя роли. Если переменная `PSQL_PROMPTn` не определена, используется общая для всех терминалов настройка `PSQL_PROMPT`.

Следующие переменные являются общими для всех терминалов:

```sh
# Приглашение, которое выводит команда паузы `p`
export PAUSE_PROMPT='.......................................................................'
# Приглашение, которое выводит команда завершения фрагмента демонстрации `P`
export PAUSE_RETURN_PROMPT='>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
```

Эти настройки обычно не меняются. TODO: сделать значениями по умолчанию и убрать из `params`.

# Общий вид демонстрации

```sh
#!/bin/bash

# topic название-темы
# demopages список-номеров-демостраниц-через-запятую

. ../lib

# Инициализация (команды не попадут в демонстрацию)

start_here демостраница-презентации

# Первый фрагмент демонстрации

P демостраница-презентации

# Следующий фрагмент демонстрации

...

P демостраница-презентации

# Последний фрагмент демонстрации

stop_here

# Финализация (команды не попадут в демонстрацию)

demo_end

# Ожидание нажатия Ctrl+C с соответствующим сообщенем


```

# Команды

## Управление сервером

Эти команды выполняются с помощью `pg_ctlcluster` или `pg_ctl`, в зависимости от значения переменной `CONTROL_имя-сервера`.

### `pgctl_start` имя-сервера
 
Запустить указанный сервер.

### `pgctl_restart` имя-сервера
 
Перезапустить указанный сервер.

### `pgctl_stop` имя-сервера
 
Остановить указанный сервер.

### `pgctl_immediate` имя-сервера
 
Остановить указанный сервер в режиме immediate.

### `pgctl_reload` имя-сервера
 
Перечитать настройки.

### `pgctl_promote` имя-сервера
 
Скомандовать реплике стать основным сервером.

### `pgctl_status` имя-сервера
 
Вывести статус указанного сервера.

### `kill_postgres` имя-сервера
 
Аварийно прервать работу указанного сервера (`kill -9`).

## Управление терминалом

### `psql_open` имя-сервера номер-терминала [доп-аргументы]

Открыть в терминале с указанным номером сеанс работы с указанным сервером. Порт подставляется из переменной сервера. Дополнительные аргументы передаются команде `psql`.

```
psql_open A 1 -d testdb -С '"SELECT version()"'
```

После открытия сеанса PID обслуживающего процесса находится в переменной `PIDn`:

```
s 1 "SELECT * FROM pg_locks WHERE pid=$PID1;"
```

### `psql_close` номер-терминала

Завершить сеанс в указанном терминале (посылает команду `\q`). Как правило, эта команда не требуется: при остановке сервера все сеансы прерываются автоматически.

## Вывод текста

### `h` текст

Выводит заголовок.

### `c` текст

Выводит обычный текст (комментарий).

### `ul` текст

Выводит пункт списка.

### `p`

Выводит `$PAUSE_PROMPT` и ждет подтверждения нажатием `Enter`.

## Управление ходом демонстрации

### `start_here` номер-слайда

Отмечает начало самого первого фрагмента демонстрации. Он будет вставлен на место указанного слайда презентации. Команды, выполняемые до этого момента, не попадут в демонстрацию. 

### `P` номер-слайда

Отмечает начало фрагмента демонстрации, который будет вставлен на место указанного слайда презентации.

Выводит `$PAUSE_RETURN_PROMPT` и ждет подтверждения нажатием `Enter`. В этом месте демонстрации преподаватель должен перейти к следующему слайду стрелкой вправо, а `Enter` нажать, когда вернется к демонстрации в следующий раз.

### `stop_here`

Отмечает конец последнего фрагмента демонстрации. Все следующие команды не попадут в демонстрацию.

Выводит `$PAUSE_RETURN_PROMPT`, чтобы сигнализировать преподавателю перейти к следующему слайду презентации. В норме преподаватель уже не вернется к демонстрации.

### `demo_end`

Выводит сообщение `Конец демонстрации. Нажмите Ctrl+C для выхода.` и ждет нажатия соответствующих клавиш.


## Выполнение команд SQL

Все следующие команды подсвечивают синтаксис при выводе SQL-команды. Подсветка реализуется утилитой `highlight`, используется файл с правилами `pgsql.lang`, охватывающий языки SQL и PL/pgSQL.

Содержимое строк, ограниченных кавычками-долларами `$язык$`, подсвечивается правилами `язык.lang` для языков perl, python, xml, js, sh. Это позволяет показывать функции на языке, отличном от SQL и PL/pgSQL:

```
s 1 "CREATE FUNCTION f() AS $python$ ... $python$ LANGUAGE plpythonu;"
```

Результат команды также можно подсветить, указав язык подсветки.

### `s` номер-терминала sql-команда [язык-подсветки]

Выполняет в указанном терминале команду SQL, переданную в виде текстовой строки (возможно, многострочной), и выводит результат. Выполнение команды подтверждается нажатием `Enter`. В результате возможна подсветка синтаксиса.

Пример:


```
s 1 "SELECT * FROM t
WHERE id = 1;"
```

### `ss` номер-терминала sql-команда

Выполняет в указанном терминале команду SQL, переданную в виде текстовой строки. Выполнение команды подтверждается нажатием `Enter`.

В отличие от `s` не считывает результат выполнения команды, поэтому не блокируется, даже если SQL-команда ожидает блокировки.

### `r` номер-терминала [язык-подсветки]

Считывает результат выполнения предыдущей команды. Используется в паре с `ss`. После выполнения в переменной RESULT содержится вывод команды. Пример:

```
s 1 "LOCK TABLE t;"
ss 2 "SELECT * FROM t;" # команда повисает на блокировке
s 1 "COMMIT;"           # блокировка снимается
r 2                     # считываем результат SELECT
```

### `si` номер-терминала sql-команда [язык-подсветки]

Как `s`, но без подтверждения команды нажатием `Enter`. Можно использовать, если команду надо выполнить сразу после предыдущей, без паузы.

### `ssi` номер-терминала sql-команда

Без подтверждения команды нажатием `Enter` и без чтения результата. Можно использовать, если команду надо выполнить сразу, а результат получить позже, после выполнения других команд.

### `s_bare` номер-терминала sql-команда

Выполняет в указанном терминале команду SQL, переданную в виде строки, и возвращает результат в виде неформатированного текста без заголовка и итоговой строки (\pset tuples_only on), ничего не выводя в терминал. Не требует подтверждения нажатием `Enter`.

Команду удобно использовать для помещения результата в переменную окружения. Пример:


```
CNT=`s_bare 1 "SELECT count(*) FROM t;"`
c "В таблице t находятся $CNT строк."
```
 
### `s_fake` номер-терминала sql-команда

Выводит команду в терминал, но не выполняет ее. Не выводит приглашение (чтобы было понятно, что команда не выполняется) и не требует подтверждения нажатием `Enter`.

### `r_only` номер-терминала sql-команда [язык-подсветки]

Выполняет в указанном терминале команду SQL, переданную в виде строки, и выводит результат, но (в отличие от `s`) не выводит саму SQL-команду. Не требует подтверждения нажатием `Enter`.

### `r_fake` номер-терминала результат-выполнения [язык-подсветки]

Выводит результат выполнения SQL-команды, переданный во втором аргументе.

Может использоваться вместе с `s_fake`, чтобы имитировать вывод и самой команды, и ее результата (см. пример ниже).

## Ожидания

Эти команды используются, чтобы сделать паузу до наступления какого-то события. Обычно применяются с репликацией, чтобы дождаться, пока изменения доедут до реплики. Базовая функция - `wait_until`. Таймаут по умолчанию - 20 секунд.

### `wait_sql` номер-терминала sql-команда [<timeout-secs>]

Ждет, пока указанная команда вернет истинное значение.

Пример:

```
s 1 "INSERT INTO t SELECT 1 FROM generate_series(1,1000);" # на мастере
wait_sql 2 "SELECT count(*) = 1000 FROM t;"                # ждем, пока на реплику приедут все строки
```

### `wait_db` номер-терминала база-данных [<timeout-secs>]

Ждет, пока появится база данных с указанным именем.

Пример:

```
s 1 "CREATE DATABASE test;" # на мастере
wait_db 2 test              # ждем, пока на реплике появится база
```

### `wait_server_ready` имя-сервера

Ждет, когда сервер начнёт принимать запросы.

Пример:

```
pgctl_start R                # systemctl может отдавать управление раньше времени
wait_server_ready R          # ждем, когда сервер восстановит согласованность и станет доступен для подключений
```

### `wait_replica_sync` номер-терминала кластер [<timeout-secs>]

Ждет, пока указанный кластер (физическая реплика) синхронизируется с нашим сервером (мастером).

Для физической репликации заменяет `wait_sql` и `wait_db`, но не работает с логической репликацией.

Ожидает, что реплика представится мастеру в формате `версия/кластер`, поэтому на реплике значение параметра `cluster_name` (или атрибута `application_name` параметра `primary_conninfo`) нужно задать именно таким (а при пакетной установке проще ничего не указывать).

Пример:

```
s 1 "CREATE DATABASE test;" # на мастере
wait_replica_sync 1 replica # ждем, пока кластер replica синхронизируется с нами
```

### `wait_param` номер-терминала имя-параметра значение-параметра [<timeout-secs>]

Ждет, когда параметр сеанса примет заданное значение. Применяется при перечитывании конфигурации, она выполняется асинхронно.

Пример:

```
s 2 "ALTER SYSTEM SET archive_command = 'exit 1';"
pgctl_reload B
wait_param 2 'archive_command' 'exit 1' # ждем, когда сеанс перечитает параметры
```

### `sleep` секунды

Обычная команда linux для вставки паузы, например, когда нужна задержка, трудно формализуемая с помощью `wait_`-команд.


### `sleep-ni` секунды

Как `sleep`, но делает паузу только в неинтерактивном режиме. Может применяться, когда в интерактивном режиме достаточно естественной паузы, которая получается, пока преподаватель нажимает `Enter`.

## Выполнение команд shell

### `eu` учетная-запись-ОС shell-команда [синтаксис]

Выполняет shell-команду от имени указанной учетной записи в ее домашнем каталоге. Команда подсвечивается правилами `sh.lang`. По умолчанию вывод команды не подсвечивается, но нужный синтаксис можно указать в необязательном аргументе.

Требует подтверждения нажатием `Enter`.

Пример - выполняем команду от имени postgres и подсвечиваем результат как SQL:

```
eu postgres "cat update_extensions.sql" pgsql
```

### `eu_fake` учетная-запись-ОС shell-команда

Выводит команду shell, но не выполняет ее. Не требует подтверждения нажатием `Enter`.

### `eu_fake_p` учетная-запись-ОС shell-команда

Выводит команду shell, но не выполняет ее. Требует подтверждения нажатием `Enter` (притворяется, что команда и в самом деле выполняется).

### `e` shell-команда [синтаксис]

То же, что `eu $OSUSER`.

### `e_fake` shell-команда

То же, что `eu_fake $OSUSER`.

### `e_fake_p` shell-команда

То же, что `eu_fake_p $OSUSER`.

### `eu_runbg` учетная-запись-ОС shell-команда

Выполняет shell-команду от имени указанной учетной записи в фоновом режиме. Можно использовать, чтобы запустить какой-нибудь продолжительный процесс (например, `pgbench`) и в процессе его работы выполнять другие команды.

Устанавливает переменные:
* BGPID - номер порожденного процесса;
* BGTMP - имя временного файла, в который перенаправляется вывод команды.

Фоновое выполнение нескольких команд не поддерживается (переменные будут перезаписаны и результат первой команды потеряется).

Используется вместе с `e_readbg` (см. ниже).

### `e_readbg`

Читает вывод команды, запущенной ранее в фоновом режиме, из файла BGTMP и затем удаляет этот файл.

Команда не ожидает завершения процесса. TODO: А почему не ожидает? Наверное надо сделать.

Пример:

```
eu_runbg student "pgbench -T 30 test"
...
wait $BGPID
e_readbg
```
### `fu учетная-запись-ОС имя-файла [синтаксис]`

Поместить данные из stdin в файл и вывести его содержимое с подсветкой синтаксиса. Используется там, где предполагается наполнять файл в текстовом редакторе.

Пример: формируем файл от имени postgres и показываем его содержимое, подсвечивая как конфигурацию.

```
fu postgres $PGDATA/postgresql.auto.conf conf << EOF
primary_conninfo="user=postgres port=5432"
EOF
```

### `f имя-файла [синтаксис]`

То же, что `fu $OSUSER`.

## Проверка ресурсов

### `require-ram` мин-гигабайт

Завершает скрипт, если общий объем оперативной памяти меньше, чем мин-гигабайт.
