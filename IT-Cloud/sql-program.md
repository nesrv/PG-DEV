### 🔹 **Учебная программа: "Основы работы с базами данных и SQL" (40 ак. ч.)**

#### **Цель курса:**

Дать слушателям базовые и практические знания по работе с реляционными базами данных и языком SQL, включая создание и управление структурами данных, выборками, обеспечением целостности и безопасности.


#

### 🔸 **Модуль 1. Введение в в базы данных и SQL (8 ак.ч.)**

**1. Введение в PostgreSQL и СУБД (2 ч.)**

* Что такое СУБД и особенности PostgreSQL
* Установка PostgreSQL (Windows/Linux)
* Инструменты: `psql`, pgAdmin, DBeaver

**2. Основы SQL: SELECT и фильтрация данных (2 ч.)**

* Базовый синтаксис SQL
* Использование переменных при выполнении команд
* Выборка даных из одной таблицы (SELECT, FROM, WHERE, ORDER BY, LIMIT)




**3. Агрегация и группировка (2 ч.)**

* COUNT, SUM, AVG, MIN, MAX
* GROUP BY и HAVING
* Встроенные функции

**4. Объединение таблиц (JOIN) (2 ч.)**

* INNER, LEFT, RIGHT, FULL JOIN
* Выборка данных из нескольких таблиц
* Вложенные запросы

### 🔸 **Модуль 2. Работа со структурами данных (10 ак.ч.)**

**5. Создание таблиц и схем (2 ч.)**

* CREATE TABLE, типы данных PostgreSQL
* PRIMARY KEY, DEFAULT, NOT NULL

**6. Модификация и удаление объектов (2 ч.)**

* ALTER TABLE: добавление/удаление столбцов
* DROP TABLE, RENAME, TRUNCATE
  **Учебные вопросы:**
* Как изменить структуру таблицы?
* Как безопасно удалить таблицу?

**7. Вставка, обновление и удаление данных (2 ч.)**

* INSERT, UPDATE, DELETE
* RETURNING и условия
  **Учебные вопросы:**
* Как обновить или удалить строки?
* Что делает команда RETURNING?

**8. Представления (Views) (1 ч.)**

* CREATE VIEW и материализованные представления
* Обновляемость представлений
  **Учебные вопросы:**
* Зачем нужны представления?
* Когда использовать материализованные VIEW?

**9. Индексы и производительность (2 ч.)**

* CREATE INDEX, UNIQUE INDEX
* EXPLAIN и план запросов
  **Учебные вопросы:**
* Как индекс влияет на производительность?
* Как читать план выполнения?

**10. Последовательности и автоинкременты (1 ч.)**

* SERIAL, BIGSERIAL
* Генерация уникальных идентификаторов
  **Учебные вопросы:**
* Как реализовать автоинкремент?
* Что такое последовательность?

---

### 🔸 **Модуль 3. Подзапросы, функции и транзакции (10 ак.ч.)**

**11. Подзапросы и выражения (2 ч.)**

* Вложенные SELECT
* EXISTS, IN, ANY, ALL
  **Учебные вопросы:**
* Когда использовать подзапросы?
* Что делает EXISTS?

**12. Встроенные функции PostgreSQL (2 ч.)**

* Строковые, числовые, даты
* COALESCE, NULLIF, CASE
  **Учебные вопросы:**
* Как обрабатывать NULL?
* Как использовать CASE для логики?

**13. Пользовательские функции (PL/pgSQL) (2 ч.)**

* CREATE FUNCTION
* BEGIN...END, IF, LOOP
  **Учебные вопросы:**
* Как создать свою функцию?
* Когда нужна логика внутри БД?

**14. Транзакции и управление изменениями (2 ч.)**

* BEGIN, COMMIT, ROLLBACK
* Точки сохранения (SAVEPOINT)
  **Учебные вопросы:**
* Что такое транзакция?
* Как отменить часть изменений?

**15. Управление конкурентным доступом (2 ч.)**

* Уровни изоляции
* Блокировки и deadlocks
  **Учебные вопросы:**
* Как PostgreSQL решает конфликты при записи?
* Что такое уровень изоляции?

---

### 🔸 **Модуль 4. Безопасность и администрирование (8 ак.ч.)**

**16. Пользователи, роли и привилегии (2 ч.)**

* CREATE ROLE, GRANT, REVOKE
* Управление доступом к таблицам
  **Учебные вопросы:**
* Как создать пользователя?
* Как ограничить доступ к таблице?

**17. Резервное копирование и восстановление (2 ч.)**

* `pg_dump`, `pg_restore`
* Backup через pgAdmin
  **Учебные вопросы:**
* Как сделать резервную копию базы?
* Как восстановить из дампа?

**18. Логирование и настройка PostgreSQL (2 ч.)**

* postgresql.conf, pg\_hba.conf
* Настройка портов, авторизации
  **Учебные вопросы:**
* Где лежит конфигурация PostgreSQL?
* Как разрешить внешние подключения?

**19. Мониторинг и диагностика (2 ч.)**

* Статистика (`pg_stat_activity`)
* Поиск медленных запросов
  **Учебные вопросы:**
* Как следить за активностью в базе?
* Как найти и оптимизировать медленные запросы?

---

### 🔸 **Завершающий блок (4 ак.ч.)**

**20. Итоговая практика и мини-проект (4 ч.)**

* Выполнение комплексного задания:

  * проектирование схемы
  * наполнение данных
  * выполнение SQL-запросов
  * создание представлений, индексов, пользователей
* Ответы на вопросы и разбор ошибок

---

Хочешь, я могу подготовить эту программу в виде PDF, презентации или сделать расписание с домашними заданиями и практикой?



день 1

Тема 1.       Введение в базы данных и SQL. 
Тема 2.       Использование переменных при выполнении команд
Тема 3.   Создание таблиц. Язык определения данных
Тема 4.       Встроенные функции и выборка данных из одной таблиц

день 2

Тема 4.       Встроенные функции и выборка данных из нескольких таблиц
Тема 5.   Вложенные запросы. Использование команд SQL*Plus
Тема 6.   Словарь данных баз данных.Представления
день 3

   


день 4

Тема 11.   Модификация таблиц и правил целостности
Тема 12.   Индексы. Последовательности.Тема 14.   

день 5

Тема 15.   Язык манипулирования данными
Тема 16.   Конкуренция и блокировка. Пользователи и защита данных