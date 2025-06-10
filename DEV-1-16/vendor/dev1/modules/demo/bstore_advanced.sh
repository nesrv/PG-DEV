#!/bin/bash

. ../lib

# Прогоняем все книжные практики, чтобы показывать финальный вариант
init 20

###############################################################################
start_here 5
h 'Демонстрация приложения'

c 'В этой демонстрации мы показываем приложение «Книжный магазин 2.0» в том виде, в котором оно будет после завершения всех практических заданий. Приложение доступно в браузере виртуальной машины курса по адресу http://localhost/'

open-file http://localhost true

P 10

###############################################################################
h 'Аутентификация'

s 1 '\c bookstore2'

c 'У нас уже есть два зарегистрированных пользователя:'

s 1 "SELECT * FROM users;"

c 'Зарегистрируем еще одного. Почтовый адрес можно указывать любой — мы будем отправлять пользователям письма, но все они попадут в локальный почтовый ящик пользователя student.'

s 1 "SELECT webapi.register_user('charlie','charlie@localhost');"

c 'Пользователь входит в систему и получает токен:'

s 1 "SELECT webapi.login('charlie');"
export TOKEN=`sudo -i -u $OSUSER psql -A -t -X -d bookstore2 -c "SELECT auth_token FROM sessions WHERE user_id = (SELECT user_id FROM users WHERE username = 'charlie') LIMIT 1"`

c 'При этом в базе появляется сеанс:'

s 1 "SELECT * FROM sessions;"

c 'Токен можно проверить функцией, закрытой для клиента:'

# показывать ошибку можно только сначала - первая версия check_auth запоминает пользователя
s 1 "SELECT username
FROM users
WHERE user_id = check_auth('00000000-0000-0000-0000-000000000000');"

s 1 "SELECT username
FROM users
WHERE user_id = check_auth('$TOKEN');"

P 12

###############################################################################
h 'Каталог книг'

c 'Информацию о книгах клиент получает функцией get_catalog. Например, для интернет-магазина:'

s 1 "SELECT book_id, title, authors_list, format, rating, price
FROM webapi.get_catalog('рефакторинг','rating','asc') \gx"

c 'Установим розничную цену для одной книги:'

s 1 "SELECT empapi.set_retail_price(6, 1000.00, now());"
s 1 "SELECT book_id, price
FROM webapi.get_catalog('рефакторинг','rating','asc');"

c 'Поступление 50 книг по 100 ₽ на склад:'

s 1 "SELECT empapi.receipt(6, 50, 100.00);"

c 'Этот вызов создает соответствующую операцию:'

s 1 "SELECT * FROM operations
WHERE book_id = 6
ORDER BY operation_id DESC
LIMIT 1 \gx"

c 'Пользователь может голосовать за книгу:'

s 1 "SELECT webapi.cast_vote('$TOKEN',6,+1);"
s 1 "SELECT book_id, votes_up, votes_down
FROM webapi.get_catalog('рефакторинг','rating','asc');"

P 14

###############################################################################
h 'Корзина'

c 'Положим книги в корзину:'

s 1 "SELECT webapi.add_to_cart(
    auth_token => '$TOKEN',
    book_id => 6,
    qty => +1 -- по умолчанию
);"
s 1 "SELECT webapi.add_to_cart(
    auth_token => '$TOKEN',
    book_id => 6
);"
s 1 "SELECT webapi.add_to_cart(
    auth_token => '$TOKEN',
    book_id => 3
);"
s 1 "SELECT webapi.add_to_cart(
    auth_token => '$TOKEN',
    book_id => 1
);"

c 'Вот что у нас в корзине:'

s 1 "SELECT *
FROM webapi.get_cart('$TOKEN') \gx"

c 'Уберем одну книгу:'

s 1 "SELECT webapi.remove_from_cart(
    auth_token => '$TOKEN',
    book_id => 1
);"

c 'И совершим покупку:'

s 1 "SELECT * FROM webapi.checkout('$TOKEN');"

c 'Что осталось в корзине?'

s 1 "SELECT book_id, title, qty, onhand_qty, price
FROM webapi.get_cart('$TOKEN') \gx"

c 'Конечно, ничего. Зато появились операции покупки:'

s 1 "SELECT * FROM operations
ORDER BY operation_id DESC
LIMIT 2 \gx"

P 16

###############################################################################
h 'Фоновые задания'

c 'Список зарегистрированных программ, которые можно выполнять как фоновые задания:'

s 1 'SELECT empapi.get_programs();'

c 'Список фоновых заданий:'

s 1 'SELECT * FROM empapi.get_tasks() \gx'

c 'Поставим в очередь на выполнение еще одно задание «Приветствие»:'

s 1 'SELECT empapi.run_program(1);'
export TASKID=`sudo -i -u $OSUSER psql -A -t -X -d bookstore2 -c "SELECT max(task_id) FROM tasks"`

c 'В ответ получаем номер задания. Немного подождем...'

sleep 3

c 'Проверим статус задания:'

s 1 "SELECT status FROM empapi.get_tasks() WHERE task_id = $TASKID;"

c 'Задание завершено. Получим результат:'

s 1 "SELECT * FROM empapi.task_results($TASKID);"

c 'Мы вернемся к фоновым заданиям позже в теме «Асинхронная обработка».'

###############################################################################

stop_here
cleanup
demo_end
