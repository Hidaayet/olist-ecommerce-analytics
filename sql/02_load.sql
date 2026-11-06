-- =============================================================================
-- 02_load.sql  |  Load clean CSVs into the olist schema
-- Run from the REPO ROOT (paths are relative to the working directory):
--     psql -d olist -f sql/01_schema.sql
--     psql -d olist -f sql/02_load.sql
-- \copy runs client-side, so it works without server file permissions.
-- Prefer Python?  python -m src.db_load   (does the same, cross-platform)
-- =============================================================================
SET search_path TO olist;

-- parents first, children after (FK order)
\copy category_translation FROM 'data/clean/category_translation.csv' WITH (FORMAT csv, HEADER true)
\copy geolocation (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, n_raw_points, geolocation_city, geolocation_state) FROM 'data/clean/geolocation.csv' WITH (FORMAT csv, HEADER true)
\copy customers FROM 'data/clean/customers.csv' WITH (FORMAT csv, HEADER true)
\copy sellers FROM 'data/clean/sellers.csv' WITH (FORMAT csv, HEADER true)
\copy products (product_id, product_category_name, product_name_length, product_description_length, product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm, product_category_name_english, has_missing_dimensions) FROM 'data/clean/products.csv' WITH (FORMAT csv, HEADER true)
\copy orders (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date, has_items, is_valid_sale, is_delivered, in_analysis_window, ts_anomaly, delivery_days, estimated_days, delay_days, is_late, purchase_month) FROM 'data/clean/orders.csv' WITH (FORMAT csv, HEADER true)
\copy order_items (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value, item_total) FROM 'data/clean/order_items.csv' WITH (FORMAT csv, HEADER true)
\copy order_payments (order_id, payment_sequential, payment_type, payment_installments, payment_value, is_zero_value) FROM 'data/clean/order_payments.csv' WITH (FORMAT csv, HEADER true)
\copy order_reviews (review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp, has_comment) FROM 'data/clean/order_reviews.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;

-- quick row counts
SELECT 'category_translation' t, COUNT(*) FROM category_translation UNION ALL
SELECT 'geolocation',  COUNT(*) FROM geolocation  UNION ALL
SELECT 'customers',    COUNT(*) FROM customers    UNION ALL
SELECT 'sellers',      COUNT(*) FROM sellers      UNION ALL
SELECT 'products',     COUNT(*) FROM products     UNION ALL
SELECT 'orders',       COUNT(*) FROM orders       UNION ALL
SELECT 'order_items',  COUNT(*) FROM order_items  UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments UNION ALL
SELECT 'order_reviews',  COUNT(*) FROM order_reviews;
