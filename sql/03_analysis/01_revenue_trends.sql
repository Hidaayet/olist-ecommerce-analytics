-- =============================================================================
-- 01_revenue_trends.sql  |  Q1: How does revenue evolve over time?
-- Revenue = SUM(price) (product revenue, excl. freight) on valid sales
-- (not canceled/unavailable) inside the analysis window (Jan 2017 - Aug 2018).
-- Techniques: CTEs, LAG, rolling window frames, running totals, FILTER.
-- =============================================================================
SET search_path TO olist;

-- 1.1 Monthly revenue, growth and rolling average -----------------------------
WITH monthly AS (
    SELECT
        purchase_month,
        COUNT(*)                                  AS orders,
        COUNT(DISTINCT customer_unique_id)        AS customers,
        SUM(items_revenue)                        AS revenue,
        SUM(freight_revenue)                      AS freight,
        SUM(items_revenue) / COUNT(*)             AS avg_order_value
    FROM vw_order_facts
    WHERE is_valid_sale AND in_analysis_window
    GROUP BY purchase_month
)
SELECT
    TO_CHAR(purchase_month, 'YYYY-MM')                                    AS month,
    orders,
    customers,
    ROUND(revenue, 0)                                                     AS revenue,
    ROUND(avg_order_value, 2)                                             AS aov,
    ROUND(100.0 * (revenue - LAG(revenue) OVER w) / NULLIF(LAG(revenue) OVER w, 0), 1)
                                                                          AS mom_growth_pct,
    ROUND(AVG(revenue) OVER (ORDER BY purchase_month
                             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS rolling_3m_avg,
    ROUND(SUM(revenue) OVER (ORDER BY purchase_month), 0)                 AS cumulative_revenue,
    -- same month last year (available Jan-Aug 2018)
    ROUND(100.0 * (revenue - LAG(revenue, 12) OVER w) / NULLIF(LAG(revenue, 12) OVER w, 0), 1)
                                                                          AS yoy_growth_pct
FROM monthly
WINDOW w AS (ORDER BY purchase_month)
ORDER BY purchase_month;

-- 1.2 Like-for-like year comparison: Jan-Aug 2017 vs Jan-Aug 2018 --------------
SELECT
    EXTRACT(YEAR FROM purchase_month)::INT          AS year,
    COUNT(*)                                        AS orders,
    COUNT(DISTINCT customer_unique_id)              AS customers,
    ROUND(SUM(items_revenue), 0)                    AS revenue,
    ROUND(SUM(items_revenue) / COUNT(*), 2)         AS aov,
    ROUND(AVG(n_items), 2)                          AS items_per_order
FROM vw_order_facts
WHERE is_valid_sale AND in_analysis_window
  AND EXTRACT(MONTH FROM purchase_month) <= 8
GROUP BY 1
ORDER BY 1;

-- 1.3 Revenue by state (top 10) with share and cumulative share ---------------
WITH by_state AS (
    SELECT customer_state, SUM(items_revenue) AS revenue, COUNT(*) AS orders
    FROM vw_order_facts
    WHERE is_valid_sale AND in_analysis_window
    GROUP BY customer_state
)
SELECT
    customer_state,
    orders,
    ROUND(revenue, 0)                                                   AS revenue,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 1)                    AS share_pct,
    ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 1)
                                                                        AS cumulative_share_pct,
    ROUND(revenue / orders, 2)                                          AS aov
FROM by_state
ORDER BY revenue DESC
LIMIT 10;

-- 1.4 When do customers buy? Day of week and hour of day ----------------------
SELECT
    TO_CHAR(order_purchase_timestamp, 'ID') || ' ' || TO_CHAR(order_purchase_timestamp, 'Dy') AS day_of_week,
    COUNT(*)                                                      AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS share_pct,
    ROUND(SUM(items_revenue) / COUNT(*), 2)                       AS aov
FROM vw_order_facts
WHERE is_valid_sale AND in_analysis_window
GROUP BY 1
ORDER BY 1;

SELECT
    EXTRACT(HOUR FROM order_purchase_timestamp)::INT              AS hour_of_day,
    COUNT(*)                                                      AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS share_pct
FROM vw_order_facts
WHERE is_valid_sale AND in_analysis_window
GROUP BY 1
ORDER BY orders DESC
LIMIT 6;

-- 1.5 Payment mix and instalment usage ---------------------------------------
SELECT
    main_payment_type,
    COUNT(*)                                             AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)   AS share_pct,
    ROUND(AVG(items_revenue), 2)                         AS avg_items_revenue,
    ROUND(AVG(max_installments), 1)                      AS avg_installments
FROM vw_order_facts
WHERE is_valid_sale AND in_analysis_window AND main_payment_type IS NOT NULL
GROUP BY main_payment_type
ORDER BY orders DESC;
