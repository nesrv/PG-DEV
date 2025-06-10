#!/bin/bash

. ../lib
init

start_here 4

###############################################################################
h 'Подпрограммы'

PSQL_PROMPT1='student=# '

c 'Создадим и подключимся к базе данных.'
s 1 "CREATE DATABASE $TOPIC_DB;"
s 1 "\c $TOPIC_DB"

c 'Создадим для удобства роль emp.'
s 1 'CREATE ROLE emp;'

c 'Создадим роли для пользователей приложения.'
s 1 'CREATE ROLE alice LOGIN IN ROLE emp;'
s 1 'CREATE ROLE bob LOGIN IN ROLE emp;'

c 'Создадим схему для объектов приложения, настроим путь поиска и предоставим права на схему ролям.'
s 1 "CREATE SCHEMA app;"
s 1 "ALTER DATABASE $TOPIC_DB SET search_path TO app, public;"
s 1 '\c'
s 1 "GRANT USAGE ON SCHEMA app TO emp;"

c 'Каждый сотрудник имеет уникальный логин и работает только в одном подразделении. Совмещение не разрешено.'
s 1 'CREATE TABLE users_depts(
  login text PRIMARY KEY,
  department text
);'

c 'Алиса и Боб работают в разных отделах одной компании.'
s 1 "INSERT INTO users_depts VALUES ('alice','PR'), ('bob','Sales');"

c 'Главная таблица приложения для учета доходов и расходов.'
s 1 'CREATE TABLE revenue(
  department text,
  amount numeric(10,2)
);'
s 1 "GRANT INSERT ON revenue TO emp;"

p

c 'Алиса входит в сеанс и заполяет таблицу данными.'
psql_open A 2 -d $TOPIC_DB -U alice
PSQL_PROMPT2='alice=> '
s 2 "INSERT INTO revenue SELECT 'PR',   -random() * 100.00 FROM generate_series(1, 2);"

c 'То же самое делает Боб.'
psql_open A 3 -d $TOPIC_DB -U bob
PSQL_PROMPT3='bob=> '
s 3 "INSERT INTO revenue SELECT 'Sales', random() * 500.00 FROM generate_series(1, 2);"

p

c 'Пользователи должны видеть данные только их отделов. Создадим для этого функцию.'
s 1 "CREATE FUNCTION getrev() RETURNS SETOF revenue
AS \$\$
SELECT * FROM revenue
WHERE department IN 
      (SELECT department FROM users_depts WHERE login = session_user)
\$\$ LANGUAGE sql;"

c 'Созданная функция по умолчанию может быть вызвана любым пользователем. По умолчанию функции получают атрибут security invoker, поэтому они выполняются с привилегиями вызывающей роли.'
s 1 '\x \df+ getrev \x'

c 'У Алисы, как и у Боба, нет прав на базовые таблицы.'
s 2 "SELECT * FROM getrev();"

c 'Если на функцию установить атрибут security definer, то функция будет работать с правами ее владельца. Это исправит ситуацию в этом случае:'
s 1 "ALTER FUNCTION getrev SECURITY DEFINER;"

c 'Теперь Алиса видит расходы своего отдела.'
s 2 "SELECT * FROM getrev();"

c 'Боб, напротив, видит доходы от продаж.'
s 3 "SELECT * FROM getrev();"

P 8
###############################################################################
h 'Представления'

c 'Права на базовые объекты представления и само представление могут отличаться. Можно воспользоваться этим для решения той же задачи - выводить содержимое таблицы в зависимости от роли в текущем сеансе.'
s 1 "CREATE VIEW vrevenue AS
	SELECT * FROM revenue WHERE department =
	(SELECT department FROM users_depts WHERE login = session_user);"
s 1 "GRANT SELECT ON vrevenue TO emp;"

c 'Проверим в сеансе Алисы:'
s 2 "SELECT * FROM vrevenue;"

c 'И Боба:'
s 3 "SELECT * FROM vrevenue;"

p

c 'По умолчанию обращения к базовым объектам представления выполняются от имени владельца представления. В 15-й версии появилась возможность выполнять запросы к представлению с правами вызывающего посредством установки свойства security_invoker.'
s 1 "ALTER VIEW vrevenue SET (security_invoker=true);"

c 'В результате запрос не работает, поскольку у Алисы и Боба привилегии на базовые таблицы представления отсутствуют.'
s 2 "SELECT * FROM vrevenue;"

c 'Предоставим членам группы emp право чтения таблицы доходов-расходов.'
s 1 "GRANT SELECT ON revenue TO emp;"

c 'Также временно позволим Алисе определять принадлежность к подразделению.'
s 1 "GRANT SELECT ON users_depts TO alice;"

c 'Теперь обращение от имени Алисы работает.'
s 2 "SELECT * FROM vrevenue;"

c 'А от имени Боба - нет.'
s 3 "SELECT * FROM vrevenue;"

P 10
###############################################################################
h 'Барьер безопасности'

c 'Если у пользователя есть возможность создавать функции, это может быть использовано для обхода ограничений безопасности.'
c 'Для проверки предоставим Алисе право создания собственных объектов в схеме app.'
s 1 "GRANT CREATE ON SCHEMA app TO alice;"

c 'Алиса создает функцию, выводящую аргументы, указывая при этом мизерную стоимость этой функции, обманывая таким образом планировщик.'
s 2 "CREATE FUNCTION penetrate(text, numeric) RETURNS bool AS 
\$\$
BEGIN
	RAISE NOTICE 'Dept % amount %', \$1, \$2;
	RETURN true;
	END;
\$\$ 
LANGUAGE plpgsql COST 0.0000000000000000000001;"

c 'Теперь эту функцию можно подставить в запрос к представлению, фильтрующему строки.'
s 2 "SELECT * FROM vrevenue WHERE penetrate(department, amount);"
c 'Представление фильтрует строки, как и раньше. Но функция выводит информацию по всем строкам, нарушая наши ограничения.'

c 'Исправить эту ситуацию можно, потребовав гарантии фильтрации перед какими-либо другими действиями.'
s 1 "ALTER VIEW vrevenue SET (security_barrier);"

c 'В результате брешь устранена:'
s 2 "SELECT * FROM vrevenue WHERE penetrate(department, amount);"

P 12
###############################################################################
h 'Функции в представлениях'

c 'Отзовем у Алисы излишние привилегии.'
s 1 "REVOKE SELECT ON users_depts FROM alice;"

c 'Заменим в представлении подзапрос, определяющий департамент работника, функцией, выполняющейся с правами владельца.'
s 1 "CREATE FUNCTION getdept() RETURNS text AS 
\$\$
	SELECT department FROM users_depts WHERE login = session_user;
\$\$ 
LANGUAGE sql SECURITY DEFINER;"

c 'Теперь заменим представление vrevenue.'
s 1 "CREATE OR REPLACE VIEW vrevenue WITH (security_invoker=true)
	AS SELECT * FROM revenue WHERE department = getdept();"
c 'На представление установлена характеристика security_invoker=true, но это никак не влияет на функцию getdept, на которую установлен SECURITY DEFINER.'

c 'Запрос от имени Алисы работает.'
s 2 "SELECT * FROM vrevenue;"

c 'И от имени Боба.'
s 3 "SELECT * FROM vrevenue;"

c 'Удалим установленное на представление свойство.'
#s 1 "ALTER VIEW vrevenue SET (security_invoker=false);"
s 1 "ALTER VIEW vrevenue RESET (security_invoker);"

p

c 'Добавим на представление право добавления данных группе emp, а также дадим возможность пользователям определять, в каких департаментах они работают.'
s 1 "GRANT INSERT ON vrevenue TO emp;"
s 1 "GRANT SELECT ON users_depts TO emp;"

c 'Потребуем чтобы PR отдел мог вставлять записи лишь о расходах, а SALES - о доходах. Вставка должна выполняться посредством представления.'
c 'Поскольку представление строится на запросе с подзапросом, для реализации вставки нам потребуется триггер. Сначала создадим триггерную функцию.'
s 1 "CREATE OR REPLACE FUNCTION app.ins_vrevenue()
 RETURNS trigger
 LANGUAGE plpgsql
AS \$\$
BEGIN
    INSERT INTO revenue
        SELECT department, 
            CASE department
                WHEN 'Sales' THEN abs(NEW.amount)
                WHEN 'PR' THEN -abs(NEW.amount)
            END
        FROM users_depts WHERE login = session_user;

    RETURN NEW;
END;
\$\$;"

c 'Теперь подключим триггер к представлению.'
s 1 "CREATE TRIGGER ins_vrevenue_trg 
	INSTEAD OF INSERT ON vrevenue 
	FOR EACH ROW EXECUTE FUNCTION ins_vrevenue();"

c 'Алиса пытается ошибочно отчитаться о доходе.'
s 2 'INSERT INTO vrevenue(amount) VALUES (1000.0);'

c 'Но ее недочет исправлен - в таблице добавился расход.'
s 2 "SELECT * FROM vrevenue;"

c 'Боб пытается внести в таблицу расход.'
s 3 'INSERT INTO vrevenue(amount) VALUES (-2000.0);'

c 'Но вставлена информация о доходе.'
s 3 "SELECT * FROM vrevenue;"

###############################################################################

stop_here

demo_end
