

Для приведения таблицы к 3НФ (третьей нормальной форме) необходимо устранить избыточные зависимости и разделить данные на несколько связанных таблиц.

**Таблица 1: Партнеры (Partners)**
* Partner_ID (PK)
* Partner_Name
* Partner_City_Code (FK)

**Таблица 2: Клиенты (Clients)**
* Client_ID (PK)
* INN_Client
* Client_Name
* Client_City_Code (FK)
* Client_Category

**Таблица 3: Города (Cities)**
* City_Code (PK)
* City_Name

**Таблица 4: Продажи (Sales)**
* Sale_ID (PK)
* Partner_ID (FK)
* Client_ID (FK)
* Sold_Date
* Reference_Code
* Sold_QTY
* Purchase_Price

**Связи между таблицами:**
* Таблица Sales ссылается на Partners через Partner_ID
* Таблица Sales ссылается на Clients через Client_ID
* Таблица Partners ссылается на Cities через Partner_City_Code
* Таблица Clients ссылается на Cities через Client_City_Code

**Заполнение таблиц:**

**Partners:**
```
Partner_ID | Partner_Name | Partner_City_Code
1000576    | КаэрМ        | 66
```

**Clients:**
```
Client_ID | INN_Client   | Client_Name | Client_City_Code | Client_Category
1         | 1234695212   | ООО Вешки   | 99               | Ритейл
```

**Cities:**
```
City_Code | City_Name
66        | Екатеринбург
99        | Москва
```

**Sales:**
```
Sale_ID | Partner_ID | Client_ID | Sold_Date       | Reference_Code | Sold_QTY | Purchase_Price
1       | 1000576    | 1         | 08.09.2021 12:49| FERT-1233      | 10       | 5000
```

Такая структура удовлетворяет требованиям 3НФ, так как:
1. Все поля зависят только от первичного ключа (1НФ)
2. Нет частичных зависимостей (2НФ)
3. Нет транзитивных зависимостей (3НФ)
4. Каждый атрибут неключевого типа зависит только от первичного ключа
5. Все данные нормализованы и не дублируются












---



## 📦 Допустим, у нас есть таблица `Sell_Out` следующей структуры:

```sql
CREATE TABLE Sell_Out (
    TransactionID INT PRIMARY KEY,
    Date DATE,
    StoreName TEXT,
    StoreAddress TEXT,
    ProductName TEXT,
    ProductCategory TEXT,
    Price DECIMAL(10,2),
    Quantity INT,
    Total DECIMAL(10,2)
);
```

---

## 🔍 Проблемы:

* **Повторяющиеся данные**: `StoreName`, `StoreAddress`, `ProductName`, `ProductCategory`.
* **Зависимость не только от ключа**: `Total` зависит от `Price * Quantity`, а не от `TransactionID` напрямую.

---

## ✅ Цель: привести к **3NF (Третья нормальная форма)**

* Удалить **повторяющиеся группы**
* Все **атрибуты должны зависеть только от первичного ключа**
* Не должно быть **транзитивных зависимостей**

---

## 🔧 Преобразование в 3NF

### 1. `Store` (магазины)

```sql
CREATE TABLE Store (
    StoreID INT PRIMARY KEY,
    StoreName TEXT,
    StoreAddress TEXT
);
```

### 2. `Product` (товары)

```sql
CREATE TABLE Product (
    ProductID INT PRIMARY KEY,
    ProductName TEXT,
    ProductCategory TEXT,
    Price DECIMAL(10,2) -- если цена фиксирована
);
```

*Если цена может меняться, то выносится в отдельную таблицу `ProductPriceHistory`.*

### 3. `Sell_Out` (транзакции)

```sql
CREATE TABLE Sell_Out (
    TransactionID INT PRIMARY KEY,
    Date DATE,
    StoreID INT,
    ProductID INT,
    Quantity INT,
    FOREIGN KEY (StoreID) REFERENCES Store(StoreID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);
```

> Поле `Total` можно не хранить, а вычислять в SELECT: `Price * Quantity`

---

## 🎯 Финальный SELECT для отчёта

```sql
SELECT
    s.Date,
    st.StoreName,
    st.StoreAddress,
    p.ProductName,
    p.ProductCategory,
    p.Price,
    s.Quantity,
    (p.Price * s.Quantity) AS Total
FROM
    Sell_Out s
JOIN Store st ON s.StoreID = st.StoreID
JOIN Product p ON s.ProductID = p.ProductID;
```

---

## 📌 Результат

Теперь структура удовлетворяет 3НФ:

* Все поля зависят **только от ключа** своей таблицы.
* **Нет дублирования данных**.
* **Нет транзитивных зависимостей**.

