Отлично! Вот SQL-запросы к 10 задачам из предложенного списка — от простых до продвинутых:

---

### ✅ **1. Книги с ФИО авторов**

```sql
SELECT 
    b.title,
    STRING_AGG(a.last_name || ' ' || a.first_name || COALESCE(' ' || a.middle_name, ''), ', ' ORDER BY au.seq_num) AS authors
FROM books b
JOIN authorship au ON b.book_id = au.book_id
JOIN authors a ON a.author_id = au.author_id
GROUP BY b.title;
```

---

### ✅ **2. Авторы без отчества**

```sql
SELECT * 
FROM authors 
WHERE middle_name IS NULL;
```

---

### ✅ **3. Авторы книги "Хрестоматия"**

```sql
SELECT a.*
FROM authors a
JOIN authorship au ON a.author_id = au.author_id
JOIN books b ON b.book_id = au.book_id
WHERE b.title = 'Хрестоматия';
```

---

### ✅ **4. Книги с одним автором**

```sql
SELECT b.title
FROM books b
JOIN authorship au ON b.book_id = au.book_id
GROUP BY b.book_id, b.title
HAVING COUNT(*) = 1;
```

---

### ✅ **5. Количество книг у каждого автора**

```sql
SELECT 
    a.last_name, a.first_name, a.middle_name,
    COUNT(DISTINCT au.book_id) AS book_count
FROM authors a
JOIN authorship au ON a.author_id = au.author_id
GROUP BY a.author_id;
```

---

### ✅ **6. Книги, написанные в соавторстве**

```sql
SELECT b.title
FROM books b
JOIN authorship au ON b.book_id = au.book_id
GROUP BY b.book_id, b.title
HAVING COUNT(*) > 1;
```

---

### ✅ **7. Последние 5 операций**

```sql
SELECT *
FROM operations
ORDER BY date_created DESC
LIMIT 5;
```

---

### ✅ **8. Книги, где первым автором не Пушкин**

```sql
SELECT b.title
FROM books b
JOIN authorship au ON b.book_id = au.book_id AND au.seq_num = 1
JOIN authors a ON au.author_id = a.author_id
WHERE NOT (a.last_name = 'Пушкин' AND a.first_name = 'Александр');
```

---

### ✅ **9. Остаток книг по складу**

```sql
SELECT 
    b.title,
    SUM(o.qty_change) AS total_qty
FROM books b
JOIN operations o ON b.book_id = o.book_id
GROUP BY b.book_id, b.title;
```

---

### ✅ **10. Авторы, работавшие с Толстым**

```sql
-- Найдём книги, где есть Толстой
WITH tolstoy_books AS (
    SELECT book_id
    FROM authorship au
    JOIN authors a ON au.author_id = a.author_id
    WHERE a.last_name = 'Толстой' AND a.first_name = 'Лев'
)
SELECT DISTINCT a.*
FROM authors a
JOIN authorship au ON a.author_id = au.author_id
WHERE au.book_id IN (SELECT book_id FROM tolstoy_books)
  AND NOT (a.last_name = 'Толстой' AND a.first_name = 'Лев');
```



