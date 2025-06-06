# Примеры вопросов и ответы для подготовки к DBA1-13

## 1. Вопросы по архитектуре PostgreSQL

**Вопрос:** Какой максимальный размер базы данных в PostgreSQL?

**Варианты ответов:**
A) 32 ТБ
B) 64 ТБ
C) 16 ТБ
D) Ограничений нет

**Правильный ответ: D**

## 2. Вопросы по командам psql

**Вопрос:** Какая команда используется для просмотра текущей версии PostgreSQL?

**Варианты:**
A) SHOW VERSION;
B) \version
C) SELECT VERSION();
D) VERSION;

**Правильный ответ: C**

## 3. Вопросы по настройке производительности

**Вопрос:** Какой параметр отвечает за размер буфера в PostgreSQL?

**Варианты:**
A) shared_buffers
B) buffer_size
C) memory_buffer
D) shared_memory

**Правильный ответ: A**

## 4. Вопросы по резервному копированию

**Вопрос:** Какая команда используется для создания логического дампа базы данных?

**Варианты:**
A) pg_dump
B) backup
C) dump_db
D) pg_backup

**Правильный ответ: A**

## 5. Вопросы по безопасности

**Вопрос:** Какой файл отвечает за настройку доступа к PostgreSQL?

**Варианты:**
A) pg_hba.conf
B) postgresql.conf
C) access.conf
D) security.conf

**Правильный ответ: A**

## 6. Вопросы по репликации

**Вопрос:** Какой тип репликации поддерживается в PostgreSQL по умолчанию?

**Варианты:**
A) Физическая репликация
B) Логическая репликация
C) Смешанная репликация
D) Репликация на уровне приложений

**Правильный ответ: A**

## 7. Вопросы по мониторингу

**Вопрос:** Какая команда используется для просмотра текущего состояния сервера?

**Варианты:**
A) \status
B) SHOW STATUS;
C) \conninfo
D) STATUS;

**Правильный ответ: C**

## 8. Вопросы по восстановлению

**Вопрос:** Какой параметр необходимо изменить для восстановления базы данных?

**Варианты:**
A) recovery_mode
B) restore_mode
C) recovery_target
D) restore_target

**Правильный ответ: C**

## 9. Вопросы по логгированию

**Вопрос:** Какой параметр отвечает за уровень логирования?

**Варианты:**
A) log_level
B) logging_level
C) log_statement
D) log_min_messages

**Правильный ответ: D**

## 10. Вопросы по оптимизации запросов

**Вопрос:** Какая команда используется для просмотра плана выполнения запроса?

**Варианты:**
A) EXPLAIN
B) SHOW PLAN
C) PLAN
D) EXPLAIN ANALYZE

**Правильный ответ: A**

### Дополнительные рекомендации:
- Практикуйтесь в написании SQL-запросов
- Изучайте документацию по командам
- Пробуйте решать задачи с ограничением по времени
- Обращайте внимание на детали в формулировках вопросов

Помните, что во время тестирования вы сможете пользоваться материалами курсов и документацией PostgreSQL, что поможет вам успешно справиться с заданиями.