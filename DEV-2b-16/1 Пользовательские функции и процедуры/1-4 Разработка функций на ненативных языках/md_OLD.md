

# Разработка функций на **ненативных языках** в PostgreSQL 

(то есть не на встроенных SQL или PL/pgSQL) — это мощная возможность, но требует дополнительных действий по настройке и безопасности. Ниже приведены основные аспекты, которые нужно учитывать при использовании **ненативных языков** в PostgreSQL, таких как Python, Perl, Tcl, Java, R и др.

---

## 🔧 1. Установка языков в PostgreSQL

Ненативные языки не включаются в PostgreSQL «из коробки». Чтобы использовать, например, `plpython3u`, `plperl` и др., их нужно:

* **Активировать расширение**:

  ```sql
  CREATE EXTENSION plpython3u;
  ```

  Для других:

  ```sql
  CREATE EXTENSION plperl;
  CREATE EXTENSION pltcl;
  ```

* **Убедиться, что язык поддерживается сборкой PostgreSQL** (например, PostgreSQL должен быть собран с поддержкой Python, Perl и т.д.). В стандартных дистрибутивах, как правило, поддержка этих языков есть, но может потребоваться установка дополнительных пакетов, например:

  * `postgresql-plpython3`
  * `postgresql-plperl`
  * `postgresql-pltcl`

---

## 🔐 2. Безопасность и язык `u`

Большинство ненативных языков идут с суффиксом `u` — например, `plpython3u`. Это значит:

* `u` = *untrusted* (небезопасный).
* Такие функции **могут выполнять произвольный код** на уровне операционной системы.
* Только **суперпользователь** может создавать такие функции.

---

## 🧠 3. Пример функции на PL/Python

```sql
CREATE EXTENSION IF NOT EXISTS plpython3u;

CREATE FUNCTION get_os_info()
RETURNS TEXT AS $$
  import platform
  return platform.platform()
$$ LANGUAGE plpython3u;
```

---

## 🧠 4. Пример на PL/Perl

```sql
CREATE EXTENSION IF NOT EXISTS plperl;

CREATE FUNCTION greet(name TEXT)
RETURNS TEXT AS $$
  return "Hello, $name!";
$$ LANGUAGE plperl;
```

---

## 🔄 5. Взаимодействие с SQL

Все ненативные языки могут:

* Принимать аргументы PostgreSQL-типа (INTEGER, TEXT, JSON и др.).
* Возвращать значения.
* Иногда — вызывать SQL-запросы через встроенные механизмы (например, `spi` в PL/Python, PL/Perl и т.д.).

### Пример вызова SQL из PL/Python:

```sql
CREATE FUNCTION get_table_count(tbl TEXT)
RETURNS INT AS $$
  plan = plpy.prepare("SELECT count(*) FROM " + tbl, [])
  result = plpy.execute(plan)
  return result[0]["count"]
$$ LANGUAGE plpython3u;
```

> ⚠️ В этом примере динамическое формирование SQL требует осторожности (SQL-инъекции!).

---

## 🧩 6. Другие расширения (через сторонние модули)

* **PL/Java** — позволяет писать функции на Java.
* **PL/V8** — JavaScript на базе Google V8.
* **PL/R** — статистический язык R.
* Установка и настройка этих расширений требует компиляции и системного доступа.

---

## 📦 Вывод

Разработка на ненативных языках в PostgreSQL:

* Даёт мощные возможности (анализ данных, ML, интеграция с внешним ПО).
* Требует внимательного подхода к безопасности.
* Часто требует прав суперпользователя.
* Хорошо подходит для написания логики, которую трудно выразить в SQL или PL/pgSQL.

