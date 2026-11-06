-- =============================================================================
-- 05_powerbi_model.sql  |  Star schema for Power BI (schema olist_bi)
--
-- Power BI imports these views. Design:
--   dimensions : dim_date, dim_customer, dim_product, dim_seller, dim_state
--   facts      : fact_orders (1 row per order), fact_order_items (1 row per item),
--                fact_cohort_retention (cohort x month index)
--   helper     : kpi_reference  (live KPI values to reconcile dashboard cards)
--
-- Requires: 00_base_views.sql, 05/06/08 analysis views, and the table
-- olist.customer_segments (created below, filled by `python -m src.run_pipeline`
-- or src/segmentation.py::publish_segments).
-- Run: psql -d olist -f sql/05_powerbi_model.sql
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS olist_bi;
SET search_path TO olist_bi, olist;

-- Segments are computed in Python (RFM, notebooks/04) and stored here -----------
CREATE TABLE IF NOT EXISTS olist.customer_segments (
    customer_unique_id TEXT PRIMARY KEY,
    orders             INTEGER NOT NULL,
    lifetime_revenue   NUMERIC(12,2) NOT NULL,
    recency_days       NUMERIC(8,1) NOT NULL,
    r_score            SMALLINT NOT NULL,
    m_score            SMALLINT NOT NULL,
    segment            TEXT NOT NULL
);

-- ---------------------------------------------------------------- dimensions
CREATE OR REPLACE VIEW olist_bi.dim_date AS
SELECT
    d::DATE                                              AS date_key,
    EXTRACT(YEAR    FROM d)::INT                         AS year,
    EXTRACT(QUARTER FROM d)::INT                         AS quarter,
    EXTRACT(MONTH   FROM d)::INT                         AS month_num,
    TO_CHAR(d, 'Mon')                                    AS month_name,
    TO_CHAR(d, 'YYYY-MM')                                AS year_month,
    DATE_TRUNC('month', d)::DATE                         AS month_start,
    EXTRACT(ISODOW FROM d)::INT                          AS iso_weekday_num,
    TO_CHAR(d, 'Dy')                                     AS weekday_name,
    EXTRACT(ISODOW FROM d) >= 6                          AS is_weekend,
    d::DATE BETWEEN DATE '2017-01-01' AND DATE '2018-08-31' AS in_analysis_window
FROM GENERATE_SERIES(TIMESTAMP '2016-09-01', TIMESTAMP '2018-10-31', INTERVAL '1 day') AS g(d);

CREATE OR REPLACE VIEW olist_bi.dim_state AS
SELECT * FROM (VALUES
 ('AC','Acre','North'),('AL','Alagoas','Northeast'),('AM','Amazonas','North'),
 ('AP','Amapa','North'),('BA','Bahia','Northeast'),('CE','Ceara','Northeast'),
 ('DF','Distrito Federal','Central-West'),('ES','Espirito Santo','Southeast'),
 ('GO','Goias','Central-West'),('MA','Maranhao','Northeast'),('MG','Minas Gerais','Southeast'),
 ('MS','Mato Grosso do Sul','Central-West'),('MT','Mato Grosso','Central-West'),
 ('PA','Para','North'),('PB','Paraiba','Northeast'),('PE','Pernambuco','Northeast'),
 ('PI','Piaui','Northeast'),('PR','Parana','South'),('RJ','Rio de Janeiro','Southeast'),
 ('RN','Rio Grande do Norte','Northeast'),('RO','Rondonia','North'),('RR','Roraima','North'),
 ('RS','Rio Grande do Sul','South'),('SC','Santa Catarina','South'),('SE','Sergipe','Northeast'),
 ('SP','Sao Paulo','Southeast'),('TO','Tocantins','North')
) AS t(state_code, state_name, region);

CREATE OR REPLACE VIEW olist_bi.dim_customer AS
SELECT
    c.customer_unique_id,
    MODE() WITHIN GROUP (ORDER BY c.customer_state)             AS state,
    COALESCE(s.orders, 0)                                       AS valid_orders,
    COALESCE(s.revenue, 0)::NUMERIC(12,2)                       AS lifetime_revenue,
    s.first_order_at::DATE                                      AS first_order_date,
    s.last_order_at::DATE                                       AS last_order_date,
    COALESCE(s.orders, 0) >= 2                                  AS is_repeat_customer,
    COALESCE(g.segment,
             CASE WHEN s.orders > 0 THEN 'After snapshot date'   -- last order on/after 2018-09-01
                  ELSE 'No valid purchase' END)                  AS segment,
    g.recency_days,
    g.r_score,
    g.m_score
FROM olist.customers c
LEFT JOIN olist.vw_customer_summary s USING (customer_unique_id)
LEFT JOIN olist.customer_segments g   USING (customer_unique_id)
GROUP BY c.customer_unique_id, s.orders, s.revenue, s.first_order_at, s.last_order_at,
         g.segment, g.recency_days, g.r_score, g.m_score;

CREATE OR REPLACE VIEW olist_bi.dim_product AS
SELECT
    product_id,
    product_category_name_english AS category,
    product_category_name         AS category_pt,
    product_photos_qty,
    product_weight_g,
    product_length_cm, product_height_cm, product_width_cm
FROM olist.products;

CREATE OR REPLACE VIEW olist_bi.dim_seller AS
SELECT seller_id, seller_city, seller_state FROM olist.sellers;

-- --------------------------------------------------------------------- facts
CREATE OR REPLACE VIEW olist_bi.fact_orders AS
SELECT
    f.order_id,
    f.order_purchase_timestamp::DATE                      AS order_date,
    f.order_purchase_timestamp                            AS order_timestamp,
    f.customer_unique_id,
    f.customer_state,
    f.order_status,
    f.is_valid_sale,
    f.is_delivered,
    f.in_analysis_window,
    f.n_items,
    f.items_revenue,
    f.freight_revenue,
    f.payment_total,
    f.main_payment_type,
    f.max_installments,
    f.delivery_days,
    f.estimated_days,
    f.delay_days,
    f.is_late,
    CASE WHEN NOT f.is_delivered THEN NULL
         WHEN f.is_late THEN 'Late' ELSE 'On time / early' END       AS delivery_outcome,
    CASE WHEN NOT f.is_delivered THEN NULL
         WHEN f.delay_days <= -7 THEN '1. 7+ days early'
         WHEN f.delay_days <= 0  THEN '2. 0-7 days early'
         WHEN f.delay_days <= 3  THEN '3. 1-3 days late'
         WHEN f.delay_days <= 7  THEN '4. 3-7 days late'
         ELSE                         '5. 7+ days late' END           AS delay_bucket,
    f.review_score,
    f.review_has_comment
FROM olist.vw_order_facts f;

CREATE OR REPLACE VIEW olist_bi.fact_order_items AS
SELECT
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    i.order_purchase_timestamp::DATE AS order_date,
    i.customer_state,
    i.is_valid_sale,
    i.in_analysis_window,
    i.price,
    i.freight_value
FROM olist.vw_item_facts i;

CREATE OR REPLACE VIEW olist_bi.fact_cohort_retention AS
SELECT
    cohort_month,
    TO_CHAR(cohort_month, 'YYYY-MM') AS cohort,
    month_index,
    cohort_size,
    active_customers,
    retention_pct
FROM olist.vw_cohort_retention;

-- ------------------------------------------- live KPI values for reconciliation
CREATE OR REPLACE VIEW olist_bi.kpi_reference AS
SELECT * FROM (
    SELECT 1 AS sort, 'Orders (valid, Jan17-Aug18)' AS kpi, COUNT(*)::NUMERIC AS value
      FROM olist_bi.fact_orders WHERE is_valid_sale AND in_analysis_window
  UNION ALL
    SELECT 2, 'Revenue R$ (items, excl. freight)', ROUND(SUM(items_revenue), 2)
      FROM olist_bi.fact_orders WHERE is_valid_sale AND in_analysis_window
  UNION ALL
    SELECT 3, 'Average order value R$', ROUND(SUM(items_revenue) / COUNT(*), 2)
      FROM olist_bi.fact_orders WHERE is_valid_sale AND in_analysis_window
  UNION ALL
    SELECT 4, 'Distinct customers', COUNT(DISTINCT customer_unique_id)::NUMERIC
      FROM olist_bi.fact_orders WHERE is_valid_sale AND in_analysis_window
  UNION ALL
    SELECT 5, 'Delivered orders', COUNT(*)::NUMERIC
      FROM olist_bi.fact_orders WHERE is_delivered AND in_analysis_window
  UNION ALL
    SELECT 6, 'Median delivery days', ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days))::NUMERIC, 2)
      FROM olist_bi.fact_orders WHERE is_delivered AND in_analysis_window
  UNION ALL
    SELECT 7, 'Late delivery rate %', ROUND(100.0 * AVG(is_late::INT), 2)
      FROM olist_bi.fact_orders WHERE is_delivered AND in_analysis_window
  UNION ALL
    SELECT 8, 'Average review score', ROUND(AVG(review_score), 3)
      FROM olist_bi.fact_orders WHERE is_valid_sale AND in_analysis_window AND review_score IS NOT NULL
  UNION ALL
    SELECT 9, '% reviews 1-2 stars', ROUND(100.0 * AVG((review_score <= 2)::INT), 2)
      FROM olist_bi.fact_orders WHERE is_valid_sale AND in_analysis_window AND review_score IS NOT NULL
  UNION ALL
    SELECT 10, 'Repeat customers % (all time)', ROUND(100.0 * AVG(is_repeat_customer::INT), 2)
      FROM olist_bi.dim_customer WHERE valid_orders >= 1
) k ORDER BY sort;
