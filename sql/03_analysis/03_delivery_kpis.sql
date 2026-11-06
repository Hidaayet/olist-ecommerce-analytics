-- =============================================================================
-- 03_delivery_kpis.sql  |  Q3: What are the delivery performance patterns?
-- Population: delivered orders (is_delivered) in the analysis window.
-- Techniques: PERCENTILE_CONT, FILTER, stage-duration decomposition, CTEs.
-- Late = delivered after the estimated date (delay_days > 0).
-- =============================================================================
SET search_path TO olist;

-- 3.1 Headline KPIs -----------------------------------------------------------
SELECT
    COUNT(*)                                                           AS delivered_orders,
    ROUND(AVG(delivery_days)::NUMERIC, 1)                              AS avg_days,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY delivery_days)::NUMERIC, 1) AS median_days,
    ROUND(PERCENTILE_CONT(0.9)  WITHIN GROUP (ORDER BY delivery_days)::NUMERIC, 1) AS p90_days,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY delivery_days)::NUMERIC, 1) AS p95_days,
    ROUND(AVG(estimated_days)::NUMERIC, 1)                             AS avg_promised_days,
    ROUND(100.0 * AVG(is_late::INT), 1)                                AS late_pct,
    ROUND(AVG(delay_days) FILTER (WHERE is_late)::NUMERIC, 1)          AS avg_days_late_when_late,
    ROUND(AVG(estimated_days - delivery_days) FILTER (WHERE NOT is_late)::NUMERIC, 1)
                                                                       AS avg_days_early_when_on_time
FROM orders
WHERE is_delivered AND in_analysis_window;

-- 3.2 Where does the time go? Stage breakdown (medians) -----------------------
SELECT
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY
        EXTRACT(EPOCH FROM order_approved_at - order_purchase_timestamp) / 86400)::NUMERIC, 2)
                                                          AS purchase_to_approval_days,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY
        EXTRACT(EPOCH FROM order_delivered_carrier_date - order_approved_at) / 86400)::NUMERIC, 2)
                                                          AS approval_to_carrier_days,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY
        EXTRACT(EPOCH FROM order_delivered_customer_date - order_delivered_carrier_date) / 86400)::NUMERIC, 2)
                                                          AS carrier_to_customer_days
FROM orders
WHERE is_delivered AND in_analysis_window AND NOT ts_anomaly
  AND order_approved_at IS NOT NULL AND order_delivered_carrier_date IS NOT NULL;

-- 3.3 Monthly trend: is service getting better or worse? ----------------------
-- CAVEAT (right-censoring): only DELIVERED orders are measured. In the last
-- months of the data, slow orders may not have arrived yet, which biases the
-- median downward. Treat the Jul-Aug 2018 medians as optimistic, not as proof
-- of improvement. Late % is less affected but not immune.
SELECT
    TO_CHAR(purchase_month, 'YYYY-MM')                                      AS month,
    COUNT(*)                                                                AS delivered,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)::NUMERIC, 1) AS median_days,
    ROUND(100.0 * AVG(is_late::INT), 1)                                     AS late_pct,
    ROUND(AVG(estimated_days)::NUMERIC, 1)                                  AS avg_promised_days
FROM orders
WHERE is_delivered AND in_analysis_window
GROUP BY purchase_month
ORDER BY purchase_month;

-- 3.4 Geography: delivery performance by customer state -----------------------
WITH by_state AS (
    SELECT
        c.customer_state                                                    AS state,
        COUNT(*)                                                            AS delivered,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.delivery_days)        AS median_days,
        AVG(o.is_late::INT)                                                 AS late_rate
    FROM orders o
    JOIN customers c USING (customer_id)
    WHERE o.is_delivered AND o.in_analysis_window
    GROUP BY c.customer_state
)
SELECT
    state,
    delivered,
    ROUND(median_days::NUMERIC, 1)                           AS median_days,
    ROUND(100 * late_rate::NUMERIC, 1)                       AS late_pct,
    RANK() OVER (ORDER BY median_days DESC)                  AS slowest_rank
FROM by_state
WHERE delivered >= 300
ORDER BY median_days DESC;

-- 3.5 Same-state vs cross-state fulfilment (single-seller orders only) --------
WITH single_seller AS (
    SELECT i.order_id, MIN(s.seller_state) AS seller_state
    FROM order_items i
    JOIN sellers s USING (seller_id)
    GROUP BY i.order_id
    HAVING COUNT(DISTINCT i.seller_id) = 1
)
SELECT
    CASE WHEN ss.seller_state = c.customer_state THEN 'same state' ELSE 'different state' END AS route,
    COUNT(*)                                                                AS orders,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.delivery_days)::NUMERIC, 1) AS median_days,
    ROUND(100.0 * AVG(o.is_late::INT), 1)                                   AS late_pct,
    ROUND(AVG(f.freight_revenue / NULLIF(f.items_revenue, 0))::NUMERIC * 100, 1) AS freight_pct_of_price
FROM orders o
JOIN customers c USING (customer_id)
JOIN single_seller ss USING (order_id)
JOIN vw_order_facts f USING (order_id)
WHERE o.is_delivered AND o.in_analysis_window
GROUP BY 1
ORDER BY 1;

-- 3.6 Peak-season stress: late rate in the Nov 2017 - Mar 2018 surge ----------
SELECT
    TO_CHAR(purchase_month, 'YYYY-MM')              AS month,
    COUNT(*)                                        AS delivered,
    ROUND(100.0 * AVG(is_late::INT), 1)             AS late_pct,
    ROUND(AVG(delay_days) FILTER (WHERE is_late)::NUMERIC, 1) AS avg_days_late
FROM orders
WHERE is_delivered AND purchase_month BETWEEN '2017-10-01' AND '2018-04-01'
GROUP BY purchase_month
ORDER BY purchase_month;
