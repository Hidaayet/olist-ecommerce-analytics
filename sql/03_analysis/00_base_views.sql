-- =============================================================================
-- 00_base_views.sql  |  Fan-out-safe analytical base views
--
-- THE rule of this project: never join items, payments and reviews to orders
-- directly. Each is one-to-many, so a naive join multiplies rows (+4.5% revenue
-- inflation measured). Aggregate each child table to ONE row per order first,
-- then join the aggregates. Every analysis query should start from these views.
--
-- Run: psql -d olist -f sql/03_analysis/00_base_views.sql
-- =============================================================================
SET search_path TO olist;

-- 1 row per order: item side ---------------------------------------------------
CREATE OR REPLACE VIEW vw_order_items_agg AS
SELECT
    order_id,
    COUNT(*)                         AS n_items,
    COUNT(DISTINCT product_id)       AS n_distinct_products,
    COUNT(DISTINCT seller_id)        AS n_sellers,
    SUM(price)                       AS items_revenue,     -- product revenue
    SUM(freight_value)               AS freight_revenue,
    SUM(price + freight_value)       AS gross_order_value
FROM order_items
GROUP BY order_id;

-- 1 row per order: payment side ------------------------------------------------
CREATE OR REPLACE VIEW vw_order_payments_agg AS
SELECT
    order_id,
    COUNT(*)                         AS n_payment_rows,
    SUM(payment_value)               AS payment_total,
    MAX(payment_installments)        AS max_installments,
    -- payment type that covered the largest share of the order
    (ARRAY_AGG(payment_type ORDER BY payment_value DESC, payment_sequential))[1]
                                     AS main_payment_type,
    BOOL_OR(payment_type = 'voucher') AS used_voucher
FROM order_payments
GROUP BY order_id;

-- 1 row per ORDER: the master fact view ---------------------------------------
CREATE OR REPLACE VIEW vw_order_facts AS
SELECT
    o.order_id,
    c.customer_unique_id,                 -- the real customer
    c.customer_state,
    c.customer_city,
    o.order_status,
    o.order_purchase_timestamp,
    o.purchase_month,
    o.is_valid_sale,
    o.is_delivered,
    o.in_analysis_window,
    o.delivery_days,
    o.estimated_days,
    o.delay_days,
    o.is_late,
    COALESCE(i.n_items, 0)            AS n_items,
    COALESCE(i.n_sellers, 0)          AS n_sellers,
    COALESCE(i.items_revenue, 0)      AS items_revenue,
    COALESCE(i.freight_revenue, 0)    AS freight_revenue,
    COALESCE(i.gross_order_value, 0)  AS gross_order_value,
    p.payment_total,
    p.max_installments,
    p.main_payment_type,
    r.review_score,
    r.has_comment                     AS review_has_comment,
    p.used_voucher,
    COALESCE(p.n_payment_rows, 0)     AS n_payment_rows
FROM orders o
JOIN customers c                 USING (customer_id)
LEFT JOIN vw_order_items_agg i    USING (order_id)
LEFT JOIN vw_order_payments_agg p USING (order_id)
LEFT JOIN order_reviews r         USING (order_id);

-- 1 row per ITEM: for category / seller / product analysis ----------------------
CREATE OR REPLACE VIEW vw_item_facts AS
SELECT
    oi.order_id,
    oi.order_item_id,
    o.purchase_month,
    o.order_purchase_timestamp,
    o.is_valid_sale,
    o.in_analysis_window,
    c.customer_unique_id,
    c.customer_state,
    oi.product_id,
    pr.product_category_name_english  AS category,
    oi.seller_id,
    s.seller_state,
    oi.price,
    oi.freight_value
FROM order_items oi
JOIN orders o     USING (order_id)
JOIN customers c  ON c.customer_id = o.customer_id
JOIN products pr  USING (product_id)
JOIN sellers s    USING (seller_id);
