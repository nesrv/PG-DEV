**Практика**

1. В двух разных базах данных находятся две таблицы с одинаковым набором столбцов.  
   Выведите строки, которые присутствуют в первой таблице, но отсутствуют во второй.  
   Решите задачу с помощью **postgres_fdw** и с помощью **dblink** и сравните два способа.

2. Как можно проверить, какой уровень изоляции использует обертка **postgres_fdw** и как она управляет соединениями и транзакциями?

---

1. Расширение **dblink** демонстрировалось в теме «Фоновые процессы».

2. Настройте на втором сервере журнал сообщений таким образом, чтобы в него записывалась информация:
   - о подключениях (`log_connections`);
   - отключениях (`log_disconnections`);
   - выполняемых командах (`log_statement`).

   Обратитесь к таблице на втором сервере с помощью **postgres_fdw** и проверьте, что попало в журнал сообщений.
