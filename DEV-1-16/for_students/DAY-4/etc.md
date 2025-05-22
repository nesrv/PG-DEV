
# Как узнать тип данных в pl/pgSQL

```sql
RAISE NOTICE '%', pg_typeof(cur);
```

[Табличные ф-ции](https://dba.stackexchange.com/questions/135378/how-to-use-returns-table-with-an-existing-table-in-postgresql)


```sh
shared_preload_libraries = '$libdir/plugin_debugger'
```