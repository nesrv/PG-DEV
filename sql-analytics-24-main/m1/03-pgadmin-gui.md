# Тема 4. Графический клиент pgAdmin

## Введение в pgAdmin

**pgAdmin** - веб-интерфейс для администрирования PostgreSQL

### Основные возможности:
- Управление серверами и базами данных
- Визуальное создание объектов БД
- Выполнение SQL запросов
- Мониторинг производительности
- Резервное копирование и восстановление

## Установка и настройка

### Установка pgAdmin:
1. Скачать с официального сайта: https://www.pgadmin.org/
2. Установить согласно инструкции для вашей ОС
3. Запустить pgAdmin (откроется в браузере)

### Первый запуск:
1. Установить мастер-пароль
2. Добавить сервер PostgreSQL
3. Настроить подключение

## Интерфейс pgAdmin

### Основные панели:
- **Browser** - дерево объектов БД
- **Query Tool** - редактор SQL запросов
- **Dashboard** - мониторинг сервера
- **Properties** - свойства объектов

### Дерево объектов:
```
Servers
└── PostgreSQL 13
    ├── Databases
    │   ├── postgres
    │   └── test_db
    │       ├── Schemas
    │       │   └── public
    │       │       ├── Tables
    │       │       ├── Views
    │       │       └── Functions
    │       ├── Extensions
    │       └── Languages
    ├── Login/Group Roles
    └── Tablespaces
```

## Практические задания

### 1. Подключение к серверу:

1. **Добавить новый сервер:**
   - Правый клик на "Servers" → "Create" → "Server"
   - Вкладка "General":
     - Name: `Local PostgreSQL`
   - Вкладка "Connection":
     - Host: `localhost`
     - Port: `5432`
     - Username: `postgres`
     - Password: `ваш_пароль`

2. **Проверить подключение:**
   - Развернуть сервер в дереве
   - Посмотреть список баз данных

### 2. Создание базы данных:

1. **Через интерфейс:**
   - Правый клик на "Databases" → "Create" → "Database"
   - Name: `company_db`
   - Owner: `postgres`
   - Нажать "Save"

2. **Через SQL:**
   - Открыть Query Tool (правый клик на БД → "Query Tool")
   - Выполнить:
   ```sql
   CREATE DATABASE hr_system;
   ```

### 3. Создание таблиц:

1. **Через интерфейс:**
   - Перейти в `company_db` → `Schemas` → `public` → `Tables`
   - Правый клик → "Create" → "Table"
   - Name: `departments`
   - Добавить столбцы:
     - `id`: integer, Primary Key, Not NULL
     - `name`: varchar(100), Not NULL
     - `budget`: numeric(10,2)

2. **Через SQL в Query Tool:**
   ```sql
   CREATE TABLE employees (
       id SERIAL PRIMARY KEY,
       first_name VARCHAR(50) NOT NULL,
       last_name VARCHAR(50) NOT NULL,
       email VARCHAR(100) UNIQUE,
       hire_date DATE,
       salary DECIMAL(10,2),
       department_id INTEGER REFERENCES departments(id)
   );
   ```

### 4. Работа с данными:

1. **Добавление данных через интерфейс:**
   - Правый клик на таблице → "View/Edit Data" → "All Rows"
   - Добавить записи в departments:
     ```
     1, 'IT', 500000.00
     2, 'HR', 200000.00
     3, 'Sales', 300000.00
     ```

2. **Добавление данных через SQL:**
   ```sql
   INSERT INTO employees (first_name, last_name, email, hire_date, salary, department_id)
   VALUES 
   ('Иван', 'Иванов', 'ivan@company.com', '2023-01-15', 80000, 1),
   ('Мария', 'Петрова', 'maria@company.com', '2023-02-01', 75000, 2),
   ('Алексей', 'Сидоров', 'alex@company.com', '2023-03-10', 90000, 1);
   ```

### 5. Выполнение запросов:

```sql
-- Простой SELECT
SELECT * FROM employees;

-- Запрос с JOIN
SELECT 
    e.first_name,
    e.last_name,
    e.salary,
    d.name as department
FROM employees e
JOIN departments d ON e.department_id = d.id;

-- Агрегатные функции
SELECT 
    d.name,
    COUNT(e.id) as employee_count,
    AVG(e.salary) as avg_salary
FROM departments d
LEFT JOIN employees e ON d.id = e.department_id
GROUP BY d.id, d.name;
```

## Полезные функции pgAdmin

### 1. Визуализация данных:
- Графики и диаграммы
- Экспорт результатов в CSV, Excel

### 2. Инструменты администрирования:
- **Backup/Restore** - резервное копирование
- **Import/Export** - импорт/экспорт данных
- **Grant Wizard** - управление правами

### 3. Мониторинг:
- **Dashboard** - общая статистика
- **Server Activity** - активные подключения
- **Lock Viewer** - просмотр блокировок

### 4. Настройки Query Tool:
- Автодополнение SQL
- Подсветка синтаксиса
- История запросов
- Объяснение планов выполнения

## Практическое задание

1. **Создайте структуру БД "Библиотека":**
   - База данных: `library`
   - Таблицы:
     - `authors` (id, name, birth_year)
     - `books` (id, title, author_id, publication_year, isbn)
     - `readers` (id, name, email, registration_date)
     - `loans` (id, book_id, reader_id, loan_date, return_date)

2. **Заполните таблицы тестовыми данными**

3. **Создайте запросы:**
   - Список всех книг с авторами
   - Книги, взятые читателями (не возвращенные)
   - Самые популярные авторы

4. **Экспортируйте результаты в CSV**

## Горячие клавиши pgAdmin

- `F5` - Выполнить запрос
- `F7` - Объяснить план запроса
- `Ctrl+Space` - Автодополнение
- `Ctrl+/` - Комментировать/раскомментировать
- `Ctrl+Shift+C` - Копировать с заголовками