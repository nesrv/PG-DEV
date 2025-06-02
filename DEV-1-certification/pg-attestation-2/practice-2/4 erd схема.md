# Схема звезда в формате ERD

```
+-------------------+       +-------------------+
|   DIM_PARTNERS    |       |    DIM_CITIES     |
+-------------------+       +-------------------+
| PK partner_key    |       | PK city_key       |
|    partner_id     |       |    city_code      |
|    partner_name   |       |    city_name      |
|    valid_from     |       |    valid_from     |
|    valid_to       |       |    valid_to       |
|    is_current     |       |    is_current     |
+-------------------+       +-------------------+
         ^                           ^
         |                           |
         |                           |
+---------------------------------------+
|             FACT_SALES                |
+---------------------------------------+
| PK sale_key                           |
|    sale_id                            |
| FK partner_key                        |
| FK date_key                           |
| FK city_key                           |
| FK product_key                        |
| FK client_key                         |
|    sold_qty                           |
|    purchase_price                     |
|    total_amount                       |
+---------------------------------------+
         |                           |
         |                           |
         v                           v
+-------------------+       +-------------------+
|   DIM_PRODUCTS    |       |    DIM_CLIENTS    |
+-------------------+       +-------------------+
| PK product_key    |       | PK client_key     |
|    reference_code |       |    inn_client     |
|    valid_from     |       |    client_name    |
|    valid_to       |       |    client_category|
|    is_current     |       | FK city_key       |
+-------------------+       |    valid_from     |
                            |    valid_to       |
                            |    is_current     |
                            +-------------------+
                                     |
                                     |
                                     v
                            +-------------------+
                            |    DIM_DATES      |
                            +-------------------+
                            | PK date_key       |
                            |    full_date      |
                            |    day_of_week    |
                            |    day_name       |
                            |    month          |
                            |    month_name     |
                            |    quarter        |
                            |    year           |
                            +-------------------+
```

## Описание ERD схемы звезда

Данная ERD-диаграмма представляет классическую схему звезда для хранилища данных о продажах. В центре находится таблица фактов **FACT_SALES**, которая связана с таблицами измерений через внешние ключи.

### Таблица фактов
- **FACT_SALES** - содержит информацию о продажах и связи со всеми измерениями

### Таблицы измерений
- **DIM_PARTNERS** - информация о поставщиках
- **DIM_CITIES** - информация о городах
- **DIM_PRODUCTS** - информация о товарах
- **DIM_CLIENTS** - информация о клиентах (имеет связь с DIM_CITIES)
- **DIM_DATES** - информация о датах

### Связи
- Таблица фактов связана с каждой таблицей измерений через соответствующий внешний ключ (FK)
- Таблица DIM_CLIENTS имеет связь с таблицей DIM_CITIES (элемент "снежинки")

### Обозначения
- **PK** - первичный ключ (Primary Key)
- **FK** - внешний ключ (Foreign Key)