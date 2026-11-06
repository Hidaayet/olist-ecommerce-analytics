-- =============================================================================
-- 02_category_pareto.sql  |  Q2: Which product categories contribute most?
-- Starts from vw_item_facts (1 row per item). Revenue = SUM(price).
-- Techniques: window functions (RANK, running SUM), Pareto / ABC classification,
-- conditional aggregation with FILTER, period-over-period comparison.
-- =============================================================================
SET search_path TO olist;

-- 2.1 Pareto: ranked categories with cumulative share and ABC class -----------
WITH cat AS (
    SELECT
        category,
        COUNT(*)                         AS items_sold,
        COUNT(DISTINCT order_id)         AS orders,
        SUM(price)                       AS revenue,
        AVG(price)                       AS avg_price
    FROM vw_item_facts
    WHERE is_valid_sale AND in_analysis_window
    GROUP BY category
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY revenue DESC)                                   AS rnk,
        100.0 * revenue / SUM(revenue) OVER ()                                AS share_pct,
        100.0 * SUM(revenue) OVER (ORDER BY revenue DESC
                                   ROWS UNBOUNDED PRECEDING) / SUM(revenue) OVER () AS cum_share_pct
    FROM cat
)
SELECT
    rnk,
    category,
    items_sold,
    ROUND(revenue, 0)          AS revenue,
    ROUND(avg_price, 2)        AS avg_price,
    ROUND(share_pct, 1)        AS share_pct,
    ROUND(cum_share_pct, 1)    AS cum_share_pct,
    CASE WHEN cum_share_pct - share_pct < 80 THEN 'A (top 80% of revenue)'
         WHEN cum_share_pct - share_pct < 95 THEN 'B (next 15%)'
         ELSE 'C (last 5%)' END AS abc_class
FROM ranked
ORDER BY rnk
LIMIT 15;

-- 2.2 How concentrated is it? Categories needed to reach 50% / 80% of revenue --
WITH cat AS (
    SELECT category, SUM(price) AS revenue
    FROM vw_item_facts
    WHERE is_valid_sale AND in_analysis_window
    GROUP BY category
),
cum AS (
    SELECT
        category,
        100.0 * SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
              / SUM(revenue) OVER ()                                          AS cum_share,
        ROW_NUMBER() OVER (ORDER BY revenue DESC)                             AS n
    FROM cat
)
SELECT
    (SELECT COUNT(*) FROM cat)                                   AS total_categories,
    MIN(n) FILTER (WHERE cum_share >= 50)                        AS categories_for_50pct,
    MIN(n) FILTER (WHERE cum_share >= 80)                        AS categories_for_80pct
FROM cum;

-- 2.3 Growth: Jan-Aug 2017 vs Jan-Aug 2018 (like-for-like months) -------------
WITH period AS (
    SELECT
        category,
        SUM(price) FILTER (WHERE purchase_month < '2018-01-01') AS rev_2017,
        SUM(price) FILTER (WHERE purchase_month >= '2018-01-01') AS rev_2018
    FROM vw_item_facts
    WHERE is_valid_sale AND in_analysis_window
      AND EXTRACT(MONTH FROM purchase_month) <= 8
    GROUP BY category
)
SELECT
    category,
    ROUND(rev_2017, 0)                                         AS rev_jan_aug_2017,
    ROUND(rev_2018, 0)                                         AS rev_jan_aug_2018,
    ROUND(100.0 * (rev_2018 - rev_2017) / NULLIF(rev_2017, 0), 0) AS growth_pct,
    ROUND(rev_2018 - rev_2017, 0)                              AS abs_change
FROM period
WHERE COALESCE(rev_2017, 0) > 100000          -- ignore tiny 2017 bases
ORDER BY abs_change DESC
LIMIT 10;

-- 2.4 Volume vs value: which categories sell cheap-and-often or rare-and-dear? -
SELECT
    category,
    COUNT(*)                                       AS items_sold,
    ROUND(AVG(price), 0)                           AS avg_price,
    ROUND(SUM(price), 0)                           AS revenue,
    ROUND(AVG(freight_value / NULLIF(price, 0)) * 100, 0) AS avg_freight_pct_of_price
FROM vw_item_facts
WHERE is_valid_sale AND in_analysis_window
GROUP BY category
HAVING COUNT(*) >= 500
ORDER BY avg_price DESC
LIMIT 8;

-- 2.5 Category x review score (quality perception by category) ----------------
SELECT
    f.category,
    COUNT(DISTINCT f.order_id)                    AS orders_reviewed,
    ROUND(AVG(r.review_score), 2)                 AS avg_review,
    ROUND(100.0 * AVG((r.review_score <= 2)::INT), 1) AS pct_1_2_star
FROM vw_item_facts f
JOIN order_reviews r USING (order_id)
WHERE f.is_valid_sale AND f.in_analysis_window
GROUP BY f.category
HAVING COUNT(DISTINCT f.order_id) >= 500
ORDER BY avg_review
LIMIT 6;
