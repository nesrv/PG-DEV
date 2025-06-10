
# 2. Преобразование типов и расширения

Обновите расширение bookfmt до версии 1.2. В новую версию добавьте преобразования типов: из book_format в jsonb и обратное преобразование из jsonb в book_format.

Проверочный запрос с форматом jsonb:

SELECT format, format::jsonb, format::jsonb::book_format FROM books LIMIT 5;
   format    |                  format                   |   format
-------------+-------------------------------------------+-------------
 (60,88,16)  | {"parts": 16, "width": 60, "height": 88}  | (60,88,16)
 (60,90,16)  | {"parts": 16, "width": 60, "height": 90}  | (60,90,16)
 (70,100,16) | {"parts": 16, "width": 70, "height": 100} | (70,100,16)
 (60,90,16)  | {"parts": 16, "width": 60, "height": 90}  | (60,90,16)
 (70,90,16)  | {"parts": 16, "width": 70, "height": 90}  | (70,90,16)

