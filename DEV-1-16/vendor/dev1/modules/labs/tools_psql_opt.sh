#!/bin/bash

. ../lib

init

psql_close 1

start_here

###############################################################################
h '1. Утилита psql и обработка ошибок внутри транзакций'

psql_open A 1

c 'Утилита psql по умолчанию работает в режиме автоматической фиксации транзакций. Поэтому любая команда SQL выполняется в отдельной транзакции.'

c 'Чтобы явно начать транзакцию, нужно выполнить команду BEGIN:'

export PSQL_PROMPT='student@student=# '
s 1 'BEGIN;'
c 'Обратите внимание на то, что приглашение psql изменилось. Символ «звездочка» говорит о том, что транзакция сейчас активна.'
export PSQL_PROMPT='student@student=*# '
s 1 'CREATE TABLE t (id int);'

c 'Предположим, мы случайно сделали ошибку в следующей команде:'
s 1 'INSERTINTO t VALUES(1);'

c 'О случившейся ошибке можно узнать из приглашения: звездочка изменилась на восклицательный знак. Попробуем исправить команду:'
export PSQL_PROMPT='student@student=!# '
s 1 'INSERT INTO t VALUES(1);'

c 'Но PostgreSQL не умеет откатывать только одну команду транзакции, поэтому транзакция обрывается и откатывается целиком. Чтобы продолжить работу, мы должны выполнить команду завершения транзакции. Не важно, будет ли это COMMIT или ROLLBACK, ведь транзакция уже отменена.'
s 1 'COMMIT;'
export PSQL_PROMPT='student@student=# '

c 'Создание таблицы было отменено, поэтому ее нет в базе данных:'
s 1 'SELECT * FROM t;'

###############################################################################
h '2. Переменная ON_ERROR_ROLLBACK'

c 'Изменим поведение psql.'
s 1 '\set ON_ERROR_ROLLBACK on'

c 'Теперь перед каждой командой транзакции неявно будет устанавливаться точка сохранения, а в случае ошибки будет происходить автоматический откат к этой точке. Это даст возможность продолжить выполнение команд транзакции.'

s 1 'BEGIN;'
export PSQL_PROMPT='student@student=*# '
s 1 'CREATE TABLE t (id int);'
s 1 'INSERTINTO t VALUES(1);'
s 1 'INSERT INTO t VALUES(1);'
s 1 'COMMIT;'
export PSQL_PROMPT='student@student=# '
s 1 'SELECT * FROM t;'

c 'Переменной ON_ERROR_ROLLBACK можно установить значение interactive, тогда подобное поведение будет только в интерактивном режиме работы, но не при выполнении скриптов.'

s 1 'DROP TABLE t;'

###############################################################################
stop_here
export PSQL_PROMPT='=> '
cleanup
demo_end
