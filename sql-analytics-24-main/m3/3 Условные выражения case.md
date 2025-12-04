## CASE 

Выражение `CASE` в `SQL` представляет собой общее условное выражение, напоминающее операторы `if/else` в других языках программирования:


```sql
CREATE TABLE test(a integer);
insert INTO test (a) values (1),(2),(3);

```



```sql
SELECT a,
    CASE 
        WHEN a=1 THEN 'one'
        WHEN a=2 THEN 'two'
        ELSE 'other'
    END
FROM test;
```


```sql
SELECT a,
    CASE a
        WHEN 1 THEN 'one'
        WHEN 2 THEN 'two'
        ELSE 'other'
    END
FROM test;
```


```sql
SELECT a,
    CASE a
        WHEN 1 THEN 'one'
        WHEN 2 THEN 'two'
        ELSE 'other'
    END
FROM test;
```