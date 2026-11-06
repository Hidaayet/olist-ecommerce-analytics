# Data dictionary

Schema `olist`, loaded from `data/clean/*.csv`. Columns marked **derived** were created by `src/cleaning.py`; all others come from the original Olist files.

## orders (99,441 rows, PK `order_id`)
| Column | Type | Description |
|---|---|---|
| order_id | text | Unique order identifier |
| customer_id | text | FK to customers. Generated per order, not a person |
| order_status | text | created, approved, invoiced, processing, shipped, delivered, canceled, unavailable |
| order_purchase_timestamp | timestamp | When the customer placed the order |
| order_approved_at | timestamp | Payment approval time |
| order_delivered_carrier_date | timestamp | Handed to the carrier |
| order_delivered_customer_date | timestamp | Delivered to the customer |
| order_estimated_delivery_date | timestamp | Delivery date promised at purchase |
| has_items | boolean | **Derived.** Order has at least one row in order_items |
| is_valid_sale | boolean | **Derived.** FALSE for canceled/unavailable. Filter on this for revenue |
| is_delivered | boolean | **Derived.** Status delivered AND delivery date present |
| in_analysis_window | boolean | **Derived.** Purchased Jan 2017 to Aug 2018 |
| ts_anomaly | boolean | **Derived.** Timestamps out of sequence (189 orders) |
| delivery_days | float | **Derived.** Purchase to delivery, in days (delivered orders only) |
| estimated_days | float | **Derived.** Purchase to estimated delivery date, in days |
| delay_days | float | **Derived.** Delivery minus estimate; positive means late |
| is_late | boolean | **Derived.** delay_days > 0 (NULL if not delivered) |
| purchase_month | date | **Derived.** First day of the purchase month |

## order_items (112,650 rows, PK `order_id + order_item_id`)
| Column | Type | Description |
|---|---|---|
| order_id | text | FK to orders |
| order_item_id | int | Sequence number of the item within the order |
| product_id | text | FK to products |
| seller_id | text | FK to sellers |
| shipping_limit_date | timestamp | Seller's deadline to hand the item to the carrier |
| price | numeric(10,2) | Item price (R$). Sum of price is product revenue |
| freight_value | numeric(10,2) | Freight charged for the item (R$) |
| item_total | numeric(10,2) | **Derived.** price + freight_value |

## order_payments (103,886 rows, PK `order_id + payment_sequential`)
| Column | Type | Description |
|---|---|---|
| order_id | text | FK to orders. An order can have several payment rows |
| payment_sequential | int | Sequence of payment methods used for the order |
| payment_type | text | credit_card, boleto, voucher, debit_card, not_defined |
| payment_installments | int | Number of instalments chosen |
| payment_value | numeric(10,2) | Amount paid with this method (R$) |
| is_zero_value | boolean | **Derived.** payment_value <= 0 (9 rows) |

## order_reviews (98,673 rows, PK `order_id`)
| Column | Type | Description |
|---|---|---|
| order_id | text | FK to orders. One review per order after cleaning |
| review_id | text | Review identifier. **Not unique** in the source data |
| review_score | smallint | 1 (worst) to 5 (best) |
| review_comment_title / review_comment_message | text | Optional free text (Portuguese) |
| review_creation_date | timestamp | Satisfaction survey sent |
| review_answer_timestamp | timestamp | Customer answered |
| has_comment | boolean | **Derived.** A comment message exists |

## customers (99,441 rows, PK `customer_id`)
| Column | Type | Description |
|---|---|---|
| customer_id | text | Key used by orders. One per order |
| customer_unique_id | text | The real customer (96,096 distinct). Use for cohorts, retention, RFM |
| customer_zip_code_prefix | char(5) | First 5 digits of the zip code (zero-padded) |
| customer_city / customer_state | text / char(2) | Location (city lowercased, accents removed) |

## products (32,951 rows, PK `product_id`)
| Column | Type | Description |
|---|---|---|
| product_category_name | text | Category in Portuguese (`unknown` if missing, 610 products) |
| product_category_name_english | text | **Derived.** English category via translation table (+3 manual mappings) |
| product_name_length, product_description_length, product_photos_qty | int | Listing quality indicators |
| product_weight_g, product_length_cm, product_height_cm, product_width_cm | numeric | Physical attributes |
| has_missing_dimensions | boolean | **Derived.** Any physical attribute missing (2 products) |

## sellers (3,095 rows, PK `seller_id`)
| Column | Type | Description |
|---|---|---|
| seller_zip_code_prefix | char(5) | Zip prefix |
| seller_city / seller_state | text / char(2) | Location |

## category_translation (74 rows, PK `product_category_name`)
71 original mappings plus `pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos` and `unknown`.

## geolocation (19,010 rows, PK `geolocation_zip_code_prefix`)
Collapsed from 1,000,163 raw points to one row per zip prefix.
| Column | Description |
|---|---|
| geolocation_lat / geolocation_lng | Median coordinates of all points in the prefix |
| n_raw_points | How many raw points were collapsed |
| geolocation_city / geolocation_state | Most frequent label for the prefix |

## Views (sql/03_analysis/00_base_views.sql)
| View | Grain | Purpose |
|---|---|---|
| vw_order_items_agg | 1 row per order | items count, items_revenue, freight, gross value |
| vw_order_payments_agg | 1 row per order | payment total, max instalments, main payment type |
| **vw_order_facts** | 1 row per order | Master view: order + real customer + item/payment aggregates + review score |
| **vw_item_facts** | 1 row per item | Category, seller and customer context for product analysis |
| vw_customer_summary | 1 row per real customer | Orders, revenue, AOV, first/last order, modal state, average review (`06_customer_value.sql`) |
| vw_cohort_retention | cohort x months since first purchase | Long-format retention table for the Power BI heat map (`05_cohorts_retention.sql`) |

## Metric definitions
| Metric | Definition |
|---|---|
| Revenue | `SUM(price)` from order_items on valid sales (excludes freight). Freight reported separately |
| Late delivery | Delivered after `order_estimated_delivery_date` |
| Analysis window | Purchases between 2017-01-01 and 2018-08-31 |


## Power BI star schema (schema `olist_bi`, `sql/05_powerbi_model.sql`)

| View | Grain | Key columns |
|---|---|---|
| dim_date | 1 row per day (2016-09 to 2018-10) | date_key, year, quarter, month_name, year_month, weekday_name, is_weekend, in_analysis_window |
| dim_state | 1 row per Brazilian state | state_code, state_name, region |
| dim_customer | 1 row per real customer (96,096) | customer_unique_id, state, valid_orders, lifetime_revenue, first/last_order_date, is_repeat_customer, segment, r_score, m_score |
| dim_product | 1 row per product | product_id, category, weight and dimensions |
| dim_seller | 1 row per seller | seller_id, seller_city, seller_state |
| fact_orders | 1 row per order (99,441) | order_id, order_date, customer_unique_id, customer_state, flags, items_revenue, freight_revenue, delivery_days, delay_days, is_late, delivery_outcome, delay_bucket, review_score |
| fact_order_items | 1 row per item (112,650) | order_id, order_item_id, product_id, seller_id, order_date, customer_state, price, freight_value, is_valid_sale |
| fact_cohort_retention | cohort x months since first order | cohort, month_index, cohort_size, active_customers, retention_pct |
| kpi_reference | 10 rows | Live KPI values to reconcile dashboard cards |

Table `olist.customer_segments` (1 row per customer with a valid purchase) is written by `src/segmentation.py` (`publish_segments`).
