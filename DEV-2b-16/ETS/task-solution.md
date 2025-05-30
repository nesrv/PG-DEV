

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

UNION

-- Подзапрос 2: Студенты, сдавшие экзамен, но не посещавшие курс
SELECT DISTINCT s.student_id, s.name, e.course, 'exam_only' AS status
FROM students s
NATURAL JOIN exams e
WHERE e.passed IS NOT NULL
EXCEPT
SELECT DISTINCT s.student_id, s.name, a.course, 'exam_only'
FROM students s
NATURAL JOIN attendance a;
```

---

### 📘 **Пояснение:**

* **`NATURAL JOIN`**: соединяет `students` с `attendance` или `exams` по `student_id`.
* **Первый EXCEPT**: находит студентов, которые были на занятиях, но не сдавали экзамен по этому курсу.
* **Второй EXCEPT**: находит студентов, которые сдали экзамен, но не были на занятиях.
* **UNION**: объединяет оба набора в финальный результат.

---

Если хочешь — могу сгенерировать тестовые данные и показать, как работает запрос на них.
