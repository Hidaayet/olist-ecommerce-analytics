-- =============================================================================
-- 06_customer_value.sql  |  Q5: Which customer segments generate the most value?
-- Customer = customer_unique_id. Value = SUM(price) over valid sales.
-- Techniques: NTILE deciles, Lorenz-style cumulative share, CTEs, segment CASE.
-- (Full RFM scoring and clustering is done in Python, Phase 4.)
-- =============================================================================
SET search_path TO olist;

CREATE OR REPLACE VIEW vw_customer_summary AS
SELECT
    customer_unique_id,
    COUNT(*)                          AS orders,
    SUM(items_revenue)                AS revenue,
    SUM(items_revenue) / COUNT(*)     AS avg_order_value,
    MIN(order_purchase_timestamp)     AS first_order_at,
    MAX(order_purchase_timestamp)     AS last_order_at,
    MODE() WITHIN GROUP (ORDER BY customer_state) AS state,
    AVG(review_score)                 AS avg_review
FROM vw_order_facts
WHERE is_valid_sale AND items_revenue > 0
GROUP BY customer_unique_id;

-- 6.1 Value deciles: how concentrated is revenue? ----------------------------------
WITH d AS (
    SELECT *, NTILE(10) OVER (ORDER BY revenue DESC) AS decile
    FROM vw_customer_summary
)
SELECT
    decile,
    COUNT(*)                                                              AS customers,
    ROUND(MIN(revenue), 0)                                                AS min_spend,
    ROUND(AVG(revenue), 0)                                                AS avg_spend,
    ROUND(SUM(revenue), 0)                                                AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)            AS share_pct,
    ROUND(100.0 * SUM(SUM(revenue)) OVER (ORDER BY decile) / SUM(SUM(revenue)) OVER (), 1) AS cum_share_pct
FROM d
GROUP BY decile
ORDER BY decile;

-- 6.2 Top slices: top 1%, 5%, 10% of customers -------------------------------------
WITH r AS (
    SELECT revenue, PERCENT_RANK() OVER (ORDER BY revenue DESC) AS pr
    FROM vw_customer_summary
)
SELECT
    label,
    ROUND(100.0 * SUM(revenue) FILTER (WHERE pr <= cutoff) / SUM(revenue), 1) AS pct_of_revenue
FROM r
CROSS JOIN (VALUES ('top 1%', 0.01), ('top 5%', 0.05), ('top 10%', 0.10), ('top 20%', 0.20)) AS t(label, cutoff)
GROUP BY label, cutoff
ORDER BY cutoff;

-- 6.3 Spend tiers -----------------------------------------------------------------
WITH t AS (
    SELECT *,
        CASE WHEN revenue >= 500 THEN '4. Premium (R$500+)'
             WHEN revenue >= 200 THEN '3. High (R$200-500)'
             WHEN revenue >= 100 THEN '2. Mid (R$100-200)'
             ELSE                     '1. Low (<R$100)' END AS tier
    FROM vw_customer_summary
)
SELECT
    tier,
    COUNT(*)                                                       AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS pct_customers,
    ROUND(SUM(revenue), 0)                                         AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)     AS pct_revenue,
    ROUND(AVG(revenue), 0)                                         AS avg_spend,
    ROUND(100.0 * AVG((orders > 1)::INT), 1)                       AS pct_repeat
FROM t
GROUP BY tier
ORDER BY tier DESC;

-- 6.4 Value by state: customers, revenue per customer, repeat rate ---------------
SELECT
    state,
    COUNT(*)                                          AS customers,
    ROUND(SUM(revenue), 0)                            AS revenue,
    ROUND(AVG(revenue), 1)                            AS revenue_per_customer,
    ROUND(AVG(avg_order_value), 1)                    AS avg_order_value,
    ROUND(100.0 * AVG((orders > 1)::INT), 2)          AS repeat_pct
FROM vw_customer_summary
GROUP BY state
HAVING COUNT(*) >= 1500
ORDER BY revenue DESC;

-- 6.5 What do high-value customers buy differently? (single-item vs basket, payment) --
SELECT
    CASE WHEN f.revenue >= 200 THEN 'High value (R$200+)' ELSE 'Other' END AS segment,
    COUNT(*)                                                    AS orders,
    ROUND(AVG(f.n_items), 2)                                    AS items_per_order,
    ROUND(AVG(f.items_revenue), 0)                              AS avg_order_value,
    ROUND(AVG(f.max_installments), 1)                           AS avg_installments,
    ROUND(100.0 * AVG((f.main_payment_type = 'credit_card')::INT), 1) AS pct_credit_card
FROM (
    SELECT o.*, c.revenue
    FROM vw_order_facts o
    JOIN vw_customer_summary c USING (customer_unique_id)
    WHERE o.is_valid_sale AND o.items_revenue > 0
) f
GROUP BY 1
ORDER BY 1 DESC;
