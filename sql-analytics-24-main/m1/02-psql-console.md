# Тема 3. Консольный клиент. Управление сервером

## Утилита psql

**psql** - интерактивный терминальный клиент для PostgreSQL

### Подключение к серверу:
```bash
psql -h hostname -p port -U username -d database
```

Параметры:
- `-h` - хост сервера (по умолчанию localhost)
- `-p` - порт (по умолчанию 5432)
- `-U` - имя пользователя
- `-d` - имя базы данных

### Примеры подключения:
```bash
# Подключение к локальному серверу
psql -U postgres

# Подключение к удаленному серверу
psql -h 192.168.1.100 -U myuser -d mydb

# Подключение с паролем
psql -U postgres -W
```

## Метакоманды psql

### Информационные команды:
```
\l          # Список баз данных
\d          # Список таблиц
\d table    # Описание таблицы
\dt         # Только таблицы
\dv         # Представления
\df         # Функции
\du         # Пользователи
```

### Навигация:
```
\c database # Подключиться к БД
\q          # Выход из psql
\h command  # Справка по SQL команде
\?          # Справка по метакомандам
```

### Работа с файлами:
```
\i file.sql     # Выполнить SQL из файла
\o file.txt     # Перенаправить вывод в файл
\o              # Вернуть вывод на экран
\copy table TO 'file.csv' CSV HEADER  # Экспорт в CSV
```

### Настройки отображения:
```
\x          # Расширенный вывод (вертикально)
\timing     # Показывать время выполнения
\pset       # Настройки форматирования
```

## Переменные psql

### Системные переменные:
```
\set        # Показать все переменные
\echo :HOST # Показать значение переменной
```

### Пользовательские переменные:
```sql
\set myvar 'Hello World'
SELECT :'myvar';
```

## Практические упражнения

### 1. Подключение и навигация:
```bash
# Подключитесь к PostgreSQL
psql -U postgres

# Посмотрите список баз данных
\l

# Создайте новую базу данных
CREATE DATABASE test_db;

# Подключитесь к новой БД
\c test_db

# Посмотрите список таблиц
\d
```

### 2. Создание и работа с таблицей:
```sql
-- Создайте таблицу
CREATE TABLE students (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    age INTEGER
);

-- Посмотрите структуру таблицы
\d students

-- Добавьте данные
INSERT INTO students (name, age) VALUES 
('Иван Иванов', 20),
('Петр Петров', 22);

-- Выберите данные
SELECT * FROM students;
```

### 3. Работа с файлами:
```sql
-- Сохраните запрос в файл
\o students.txt
SELECT * FROM students;
\o

-- Создайте SQL файл
\! echo "SELECT COUNT(*) FROM students;" > count.sql

-- Выполните файл
\i count.sql
```

### 4. Настройки отображения:
```sql
-- Включите расширенный вывод
\x

-- Посмотрите данные
SELECT * FROM students;

-- Включите показ времени
\timing

-- Выполните запрос
SELECT * FROM students;
```

## Полезные команды системы

### Управление сервером (Linux/Mac):
```bash
# Запуск сервера
pg_ctl start -D /path/to/data

# Остановка сервера
pg_ctl stop -D /path/to/data

# Перезапуск
pg_ctl restart -D /path/to/data

# Статус
pg_ctl status -D /path/to/data
```

### Создание пользователя и БД:
```bash
# Создать пользователя
createuser -U postgres myuser

# Создать БД
createdb -U postgres -O myuser mydb

# Удалить БД
dropdb -U postgres mydb
```

## Домашнее задание

1. Подключитесь к PostgreSQL через psql
2. Создайте базу данных `practice`
3. Создайте таблицу `employees` с полями: id, name, position, salary
4. Добавьте 5 записей
5. Экспортируйте данные в CSV файл
6. Сохраните все команды в файл `homework.sql`