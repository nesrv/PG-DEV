# Самостоятельная работа

## ТЕОРИЯ


[Тест-1](https://htmlpreview.github.io/?https://github.com/nesrv/dev-1-12/blob/main/test-day-1.html)

## ПРАКТИКА

### Практика-1

1. Установите в postgresql.conf для параметра work_mem значение 8 Мбайт.

Обновите конфигурацию и проверьте, что изменения вступили в силу.

2. Запишите в файл ddl.sql команду CREATE TABLE на создание любой таблицы. 

Запишите в файл populate.sql команды на вставку строкв эту таблицу.

Войдите в psql, выполните оба скрипта и проверьте, что таблица создалась и в ней появились записи.

3. Найдите в журнале сервера строки за сегодняшний день.


### Практика-2

1. Создайте таблицу с одной строкой. 

Начните первую транзакцию на уровне изоляции Read Committed и выполните запрос к таблице.

Во втором сеансе удалите строку и зафиксируйте изменения.

Сколько строк увидит первая транзакция, выполнив тот же запрос повторно? Проверьте. 

Завершите первую транзакцию.

2. Повторите все то же самое, но пусть теперь транзакция работает на уровне изоляции Repeatable Read: 

BEGIN ISOLATION LEVEL REPEATABLE READ; Объясните отличия


### Практика-3

1. Проверьте, как используется буферный кеш в случае обновления одной строки в обычной и во временной таблице. 

Попробуйте объяснить отличие.

2. Создайте нежурналируемую таблицу и вставьте в нее несколько строк. 

Сымитируйте сбой системы, остановив сервер в режиме immediate, как в демонстрации.

Запустите сервер и проверьте, что произошло с таблицей.

Найдите в журнале сообщений сервера упоминаниео восстановлении после сбоя.