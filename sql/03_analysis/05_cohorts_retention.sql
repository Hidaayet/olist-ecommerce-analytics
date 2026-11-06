-- =============================================================================
-- 05_cohorts_retention.sql  |  Q6: How does purchasing behaviour evolve across cohorts?
-- Customer = customer_unique_id (NEVER customer_id; see decisions log D-01).
-- Cohort  = month of a customer's first valid purchase.
-- Techniques: ROW_NUMBER, MIN() OVER (PARTITION BY), date arithmetic, pivot with
-- FILTER, LEAD, PERCENTILE_CONT. Activity is capped at Aug 2018 (last full month).
-- Expect LOW retention: only ~3% of Olist customers ever order twice.
-- =============================================================================
SET search_path TO olist;

-- 5.1 Cohort retention in long format, as a VIEW (feeds the Power BI heat map) ---
CREATE OR REPLACE VIEW vw_cohort_retention AS
WITH valid_orders AS (
    SELECT customer_unique_id, purchase_month
    FROM vw_order_facts
    WHERE is_valid_sale AND purchase_month <= DATE '2018-08-01'
),
cohorts AS (
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
    FROM valid_orders
    GROUP BY customer_unique_id
),
activity AS (
    SELECT DISTINCT
        c.cohort_month,
        v.customer_unique_id,
        (EXTRACT(YEAR  FROM AGE(v.purchase_month, c.cohort_month)) * 12
       + EXTRACT(MONTH FROM AGE(v.purchase_month, c.cohort_month)))::INT AS month_index
    FROM valid_orders v
    JOIN cohorts c USING (customer_unique_id)
),
sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size FROM cohorts GROUP BY cohort_month
)
SELECT
    a.cohort_month,
    s.cohort_size,
    a.month_index,
    COUNT(*)                                   AS active_customers,
    ROUND(100.0 * COUNT(*) / s.cohort_size, 2) AS retention_pct
FROM activity a
JOIN sizes s USING (cohort_month)
WHERE a.cohort_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
  AND a.month_index BETWEEN 0 AND 12
GROUP BY a.cohort_month, s.cohort_size, a.month_index;

-- peek: retention by months since first purchase (cohorts weighted by size)
SELECT
    month_index,
    SUM(active_customers)                                      AS active_customers,
    ROUND(100.0 * SUM(active_customers) / SUM(cohort_size), 2) AS weighted_retention_pct
FROM vw_cohort_retention
WHERE month_index BETWEEN 1 AND 6
  AND cohort_month <= DATE '2018-02-01'     -- only cohorts that have had 6 months to return
GROUP BY month_index
ORDER BY month_index;

-- 5.2 Pivot: retention % at M1, M2, M3, M6 per cohort ---------------------------
WITH valid_orders AS (
    SELECT customer_unique_id, purchase_month
    FROM vw_order_facts
    WHERE is_valid_sale AND purchase_month <= DATE '2018-08-01'
),
cohorts AS (
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
    FROM valid_orders GROUP BY customer_unique_id
),
activity AS (
    SELECT DISTINCT
        c.cohort_month, v.customer_unique_id,
        (EXTRACT(YEAR  FROM AGE(v.purchase_month, c.cohort_month)) * 12
       + EXTRACT(MONTH FROM AGE(v.purchase_month, c.cohort_month)))::INT AS m
    FROM valid_orders v JOIN cohorts c USING (customer_unique_id)
)
SELECT
    TO_CHAR(cohort_month, 'YYYY-MM')                                           AS cohort,
    COUNT(*) FILTER (WHERE m = 0)                                              AS cohort_size,
    ROUND(100.0 * COUNT(*) FILTER (WHERE m = 1) / COUNT(*) FILTER (WHERE m = 0), 2) AS m1_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE m = 2) / COUNT(*) FILTER (WHERE m = 0), 2) AS m2_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE m = 3) / COUNT(*) FILTER (WHERE m = 0), 2) AS m3_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE m = 6) / COUNT(*) FILTER (WHERE m = 0), 2) AS m6_pct
FROM activity
WHERE cohort_month BETWEEN DATE '2017-01-01' AND DATE '2018-02-01'   -- cohorts old enough for M6
GROUP BY cohort_month
ORDER BY cohort_month;

-- 5.3 Overall repeat behaviour -------------------------------------------------
WITH per_customer AS (
    SELECT customer_unique_id, COUNT(*) AS orders, SUM(items_revenue) AS revenue
    FROM vw_order_facts
    WHERE is_valid_sale
    GROUP BY customer_unique_id
)
SELECT
    CASE WHEN orders >= 3 THEN '3+ orders' ELSE orders || ' order' || CASE WHEN orders > 1 THEN 's' ELSE '' END END AS segment,
    COUNT(*)                                                    AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_of_customers,
    ROUND(SUM(revenue), 0)                                      AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)  AS pct_of_revenue,
    ROUND(AVG(revenue), 2)                                      AS avg_revenue_per_customer
FROM per_customer
GROUP BY 1
ORDER BY 1;

-- 5.4 Time to second order -------------------------------------------------------
WITH seq AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp AS ts,
        ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, order_id) AS n
    FROM vw_order_facts
    WHERE is_valid_sale
),
gaps AS (
    SELECT
        a.customer_unique_id,
        EXTRACT(EPOCH FROM (b.ts - a.ts)) / 86400 AS days_to_second
    FROM seq a JOIN seq b
      ON a.customer_unique_id = b.customer_unique_id AND a.n = 1 AND b.n = 2
)
SELECT
    COUNT(*)                                                                    AS customers_with_2nd_order,
    ROUND(100.0 * AVG((days_to_second < 1)::INT), 1)                            AS pct_within_1_day,
    ROUND(100.0 * AVG((days_to_second < 30)::INT), 1)                           AS pct_within_30_days,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY days_to_second)::NUMERIC, 0) AS p25_days,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY days_to_second)::NUMERIC, 0) AS median_days,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY days_to_second)::NUMERIC, 0) AS p75_days
FROM gaps;

-- 5.5 Does the first experience predict a repeat purchase? ------------------------
-- Only customers whose first order allows a full 180-day window
-- (first order <= 2018-02-28, data ends 2018-08-31). A repeat = a 2nd valid order
-- within 180 days. Order 1 is joined to order 2 once (a correlated EXISTS over a
-- CTE re-scans it per row: O(n^2), it ran for 5+ minutes).
DROP TABLE IF EXISTS tmp_first_second;
CREATE TEMP TABLE tmp_first_second AS
WITH seq AS (
    SELECT
        customer_unique_id, order_purchase_timestamp AS ts,
        review_score, is_late, is_delivered,
        ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                           ORDER BY order_purchase_timestamp, order_id) AS n
    FROM vw_order_facts
    WHERE is_valid_sale
)
SELECT
    f.customer_unique_id,
    f.review_score  AS first_review_score,
    f.is_late       AS first_is_late,
    f.is_delivered  AS first_is_delivered,
    (s.ts IS NOT NULL AND s.ts <= f.ts + INTERVAL '180 days') AS repeated_180d
FROM seq f
LEFT JOIN seq s ON s.customer_unique_id = f.customer_unique_id AND s.n = 2
WHERE f.n = 1 AND f.ts <= TIMESTAMP '2018-02-28';

SELECT
    first_review_score                                    AS first_order_review,
    COUNT(*)                                              AS customers,
    ROUND(100.0 * AVG(repeated_180d::INT), 2)             AS repeat_within_180d_pct
FROM tmp_first_second
WHERE first_review_score IS NOT NULL
GROUP BY first_review_score
ORDER BY first_review_score;

SELECT
    CASE WHEN first_is_late THEN 'first delivery late' ELSE 'first delivery on time' END AS first_order,
    COUNT(*)                                              AS customers,
    ROUND(100.0 * AVG(repeated_180d::INT), 2)             AS repeat_within_180d_pct
FROM tmp_first_second
WHERE first_is_delivered
GROUP BY first_is_late
ORDER BY first_is_late;

-- 5.6 Repeat buyers by state (where is loyalty strongest?) ------------------------
WITH per_customer AS (
    SELECT customer_unique_id, MIN(customer_state) AS state, COUNT(*) AS orders
    FROM vw_order_facts WHERE is_valid_sale
    GROUP BY customer_unique_id
)
SELECT
    state,
    COUNT(*)                                          AS customers,
    ROUND(100.0 * AVG((orders > 1)::INT), 2)          AS repeat_customer_pct
FROM per_customer
GROUP BY state
HAVING COUNT(*) >= 1000
ORDER BY repeat_customer_pct DESC;
