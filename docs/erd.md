# Entity-relationship diagram

GitHub renders this diagram automatically. Solid lines are enforced foreign keys; dotted lines are soft joins (no FK, see note below).

```mermaid
erDiagram
    CUSTOMERS ||--o{ ORDERS : "places (1 customer_id per order)"
    ORDERS ||--o{ ORDER_ITEMS : contains
    ORDERS ||--o{ ORDER_PAYMENTS : "paid by"
    ORDERS ||--o| ORDER_REVIEWS : "reviewed in"
    PRODUCTS ||--o{ ORDER_ITEMS : "sold as"
    SELLERS ||--o{ ORDER_ITEMS : "fulfils"
    CATEGORY_TRANSLATION ||--o{ PRODUCTS : classifies
    GEOLOCATION |o..o{ CUSTOMERS : "zip prefix (soft)"
    GEOLOCATION |o..o{ SELLERS : "zip prefix (soft)"

    CUSTOMERS {
        text customer_id PK "one per ORDER"
        text customer_unique_id "the real person"
        char5 customer_zip_code_prefix
        text customer_city
        char2 customer_state
    }
    ORDERS {
        text order_id PK
        text customer_id FK
        text order_status
        timestamp order_purchase_timestamp
        timestamp order_estimated_delivery_date
        boolean is_valid_sale
        boolean is_delivered
        float delivery_days
        float delay_days
        boolean is_late
        date purchase_month
    }
    ORDER_ITEMS {
        text order_id PK, FK
        int order_item_id PK
        text product_id FK
        text seller_id FK
        numeric price
        numeric freight_value
    }
    ORDER_PAYMENTS {
        text order_id PK, FK
        int payment_sequential PK
        text payment_type
        int payment_installments
        numeric payment_value
    }
    ORDER_REVIEWS {
        text order_id PK, FK
        text review_id "not unique"
        smallint review_score
        timestamp review_creation_date
    }
    PRODUCTS {
        text product_id PK
        text product_category_name FK
        text product_category_name_english
        numeric product_weight_g
    }
    SELLERS {
        text seller_id PK
        char5 seller_zip_code_prefix
        char2 seller_state
    }
    CATEGORY_TRANSLATION {
        text product_category_name PK
        text product_category_name_english
    }
    GEOLOCATION {
        char5 geolocation_zip_code_prefix PK
        float geolocation_lat
        float geolocation_lng
    }
```

## Modelling notes

- **Grain.** `orders` = 1 row per order. `order_items` = 1 row per item in an order. `order_payments` = 1 row per payment instalment/method. `order_reviews` = 1 row per order (after de-duplication).
- **The person is not `customer_id`.** `customers` has 99,441 rows but only 96,096 distinct `customer_unique_id`. Cohorts and RFM must group by `customer_unique_id`.
- **Why no FK to `geolocation`?** 279 customer and 7 seller zip prefixes have no coordinates, so an FK would reject valid rows. The zip join is optional, and map visuals simply skip those points.
- **Fan-out protection.** Analysis queries start from `vw_order_facts` (1 row per order) or `vw_item_facts` (1 row per item), never from raw multi-table joins.
