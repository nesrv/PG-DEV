
Давайте разберём задачу пошагово.

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

