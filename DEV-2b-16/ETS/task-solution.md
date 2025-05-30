

### ✅ **SQL-запрос:**

```sql
-- Подзапрос 1: Студенты, посещавшие курс, но не сдававшие экзамен по нему
SELECT DISTINCT s.student_id, s.name, a.course, 'attended_only' AS status
FROM students s
NATURAL JOIN attendance a
EXCEPT
SELECT DISTINCT s.student_id, s.name, e.course, 'attended_only'
FROM students s
NATURAL JOIN exams e
WHERE e.passed IS NOT NULL;



-- проще
SELECT student_id, name, course, 'attended_only' AS status
FROM students
NATURAL JOIN attendance
EXCEPT
SELECT student_id, name, course, 'attended_only'
FROM students
NATURAL JOIN exams
WHERE passed IS NOT NULL;




-- Подзапрос 2: Студенты, сдавшие экзамен, но не посещавшие курс
SELECT DISTINCT s.student_id, s.name, e.course, 'exam_only' AS status
FROM students s
NATURAL JOIN exams e
WHERE e.passed IS NOT NULL
EXCEPT
SELECT DISTINCT s.student_id, s.name, a.course, 'exam_only'
FROM students s
NATURAL JOIN attendance a;



--проще

SELECT student_id, name, course, 'exam_only' AS status
FROM students
NATURAL JOIN exams
WHERE passed IS NOT NULL
EXCEPT
SELECT student_id, name, course, 'exam_only'
FROM students
NATURAL JOIN attendance;
```

---

### 📘 **Пояснение:**

* **`NATURAL JOIN`**: соединяет `students` с `attendance` или `exams` по `student_id`.
* **Первый EXCEPT**: находит студентов, которые были на занятиях, но не сдавали экзамен по этому курсу.
* **Второй EXCEPT**: находит студентов, которые сдали экзамен, но не были на занятиях.
* **UNION**: объединяет оба набора в финальный результат.

---

Если хочешь — могу сгенерировать тестовые данные и показать, как работает запрос на них.
