-- =============================================================================
-- 07_data_quality_investigations.sql  |  Closes the open questions in docs/decisions_log.md
--   (a) Why do ~0.4% of orders have payments that differ from items value?
--   (b) What are the 189 timestamp-sequence anomalies?
-- =============================================================================
SET search_path TO olist;

-- (a) Payment vs item value mismatches ---------------------------------------------
-- 7.1 Size and direction of the gap
WITH m AS (
    SELECT order_id, gross_order_value, payment_total, main_payment_type,
           max_installments, used_voucher, n_items,
           payment_total - gross_order_value AS diff
    FROM vw_order_facts
    WHERE items_revenue > 0 AND payment_total IS NOT NULL
)
SELECT
    CASE WHEN ABS(diff) <= 0.01 THEN 'match'
         WHEN diff > 0 THEN 'paid MORE than items+freight'
         ELSE 'paid LESS than items+freight' END                     AS category,
    COUNT(*)                                                         AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)               AS pct,
    ROUND(AVG(diff)::NUMERIC, 2)                                     AS avg_diff,
    ROUND(SUM(diff)::NUMERIC, 0)                                     AS total_diff,
    ROUND(100.0 * AVG(used_voucher::INT), 1)                         AS pct_voucher,
    ROUND(AVG(max_installments), 1)                                  AS avg_installments
FROM m
GROUP BY 1
ORDER BY orders DESC;

-- 7.2 Which payment types are associated with a mismatch?
WITH m AS (
    SELECT main_payment_type, ABS(payment_total - gross_order_value) > 0.01 AS mismatch,
           payment_total > gross_order_value AS overpaid, max_installments
    FROM vw_order_facts
    WHERE items_revenue > 0 AND payment_total IS NOT NULL
)
SELECT
    main_payment_type,
    COUNT(*)                                                    AS orders,
    ROUND(100.0 * AVG(mismatch::INT), 2)                        AS mismatch_pct,
    ROUND(100.0 * AVG(overpaid::INT) FILTER (WHERE mismatch), 1) AS pct_of_mismatches_overpaid
FROM m
GROUP BY main_payment_type
ORDER BY mismatch_pct DESC;

-- 7.3 Credit-card mismatches by instalment count (interest hypothesis)
SELECT
    CASE WHEN max_installments = 1 THEN '1'
         WHEN max_installments <= 3 THEN '2-3'
         WHEN max_installments <= 6 THEN '4-6'
         ELSE '7+' END                                            AS installments,
    COUNT(*)                                                      AS orders,
    ROUND(100.0 * AVG((payment_total - gross_order_value > 0.01)::INT), 2) AS pct_overpaid
FROM vw_order_facts
WHERE items_revenue > 0 AND payment_total IS NOT NULL AND main_payment_type = 'credit_card'
GROUP BY 1
ORDER BY 1;

-- (b) Timestamp-sequence anomalies ---------------------------------------------------
-- 7.4 Which rule is broken, and in which statuses?
SELECT
    COUNT(*) FILTER (WHERE order_approved_at < order_purchase_timestamp)              AS approved_before_purchase,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date < order_purchase_timestamp)   AS carrier_before_purchase,
    COUNT(*) FILTER (WHERE order_delivered_customer_date < order_delivered_carrier_date) AS delivered_before_carrier,
    COUNT(*) FILTER (WHERE ts_anomaly)                                                AS total_anomalous_orders
FROM orders;

SELECT order_status, COUNT(*) AS anomalous_orders
FROM orders WHERE ts_anomaly
GROUP BY order_status ORDER BY 2 DESC;

-- 7.5 Are anomalies clustered in time or in sellers?
SELECT
    TO_CHAR(purchase_month, 'YYYY-MM')        AS month,
    COUNT(*) FILTER (WHERE ts_anomaly)        AS anomalies,
    COUNT(*)                                  AS orders,
    ROUND(100.0 * AVG(ts_anomaly::INT), 2)    AS anomaly_pct
FROM orders
GROUP BY purchase_month
HAVING COUNT(*) FILTER (WHERE ts_anomaly) > 0
ORDER BY anomalies DESC
LIMIT 6;

WITH seller_orders AS (
    SELECT DISTINCT i.seller_id, o.order_id, o.ts_anomaly
    FROM order_items i JOIN orders o USING (order_id)
)
SELECT
    seller_id,
    COUNT(*)                                   AS orders,
    COUNT(*) FILTER (WHERE ts_anomaly)         AS anomalies,
    ROUND(100.0 * AVG(ts_anomaly::INT), 1)     AS anomaly_pct
FROM seller_orders
GROUP BY seller_id
HAVING COUNT(*) FILTER (WHERE ts_anomaly) >= 5
ORDER BY anomalies DESC
LIMIT 5;

-- 7.6 Impact: do anomalies distort delivery KPIs? (delivered orders)
SELECT
    ts_anomaly,
    COUNT(*)                                                        AS orders,
    ROUND(AVG(delivery_days)::NUMERIC, 2)                           AS avg_delivery_days,
    ROUND(100.0 * AVG(is_late::INT), 2)                             AS late_pct
FROM orders
WHERE is_delivered
GROUP BY ts_anomaly;
