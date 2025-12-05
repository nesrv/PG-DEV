-- =====================================================
-- База данных библиотеки
-- =====================================================

-- Таблица авторов
CREATE TABLE authors (
    author_id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    last_name TEXT NOT NULL,
    first_name TEXT NOT NULL,
    middle_name TEXT
);

-- Таблица книг
CREATE TABLE books (
    book_id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    title TEXT NOT NULL
);

-- Таблица авторства (связь многие-ко-многим)
CREATE TABLE authorship (
    book_id INTEGER REFERENCES books(book_id),
    author_id INTEGER REFERENCES authors(author_id),
    seq_num INTEGER NOT NULL,
    PRIMARY KEY (book_id, author_id)
);

-- Таблица операций с книгами
CREATE TABLE operations (
    operation_id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    book_id INTEGER NOT NULL REFERENCES books(book_id),
    qty_change INTEGER NOT NULL,
    date_created DATE NOT NULL DEFAULT CURRENT_DATE
);

-- =====================================================
-- Заполнение данными
-- =====================================================

-- Авторы
INSERT INTO authors (last_name, first_name, middle_name) VALUES
    ('Пушкин', 'Александр', 'Сергеевич'),
    ('Тургенев', 'Иван', 'Сергеевич'),
    ('Стругацкий', 'Борис', 'Натанович'),
    ('Стругацкий', 'Аркадий', 'Натанович'),
    ('Толстой', 'Лев', 'Николаевич'),
    ('Свифт', 'Джонатан', NULL);

-- Книги
INSERT INTO books (title) VALUES
    ('Сказка о царе Салтане'),
    ('Муму'),
    ('Трудно быть богом'),
    ('Война и мир'),
    ('Путешествия в некоторые удаленные страны мира в четырех частях: сочинение Лемюэля Гулливера, сначала хирурга, а затем капитана нескольких кораблей'),
    ('Хрестоматия');

-- Авторство (связь книг и авторов)
INSERT INTO authorship (book_id, author_id, seq_num) VALUES
    (1, 1, 1),  -- Сказка о царе Салтане - Пушкин
    (2, 2, 1),  -- Муму - Тургенев
    (3, 4, 1),  -- Трудно быть богом - А. Стругацкий (первый автор)
    (3, 3, 2),  -- Трудно быть богом - Б. Стругацкий (второй автор)
    (4, 5, 1),  -- Война и мир - Толстой
    (5, 6, 1),  -- Путешествия Гулливера - Свифт
    (6, 1, 1),  -- Хрестоматия - Пушкин (первый)
    (6, 5, 2),  -- Хрестоматия - Толстой (второй)
    (6, 2, 3);  -- Хрестоматия - Тургенев (третий)

-- Операции с книгами (поступления и списания)
INSERT INTO operations (book_id, qty_change) VALUES
    (1, 10),   -- Поступило 10 экземпляров "Сказки о царе Салтане"
    (1, 10),   -- Поступило еще 10 экземпляров
    (1, -1);   -- Списан 1 экземпляр
    (2, 5),    -- Поступило 5 экземпляров "Муму"
    (3, 3),    -- Поступило 3 экземпляра "Трудно быть богом"
    (4, 2),    -- Поступило 2 экземпляра "Война и мир"
    (5, 1);    -- Поступил 1 экземпляр "Путешествия Гулливера"