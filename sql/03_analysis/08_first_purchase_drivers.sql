-- =============================================================================
-- 08_first_purchase_drivers.sql  |  Q6 (cont.): what about a customer's FIRST
-- purchase predicts whether they ever come back?  Tests the hypothesis from
-- docs/analysis_findings.md that low retention is structural (one-off categories).
--
-- vw_first_order_profile: 1 row per real customer = attributes of their first
-- valid order + timestamp of their 2nd order (if any). Order 1 is joined to
-- order 2 once; no correlated subqueries (those are O(n^2), see decisions D-17).
-- "Repeat" excludes 2nd orders placed within 24h of the first (split baskets).
-- =============================================================================
SET search_path TO olist;

CREATE OR REPLACE VIEW vw_first_order_profile AS
WITH seq AS MATERIALIZED (
    SELECT
        customer_unique_id, order_id, order_purchase_timestamp AS ts,
        items_revenue, n_items, main_payment_type, max_installments,
        customer_state, review_score, is_late, is_delivered,
        ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                           ORDER BY order_purchase_timestamp, order_id) AS n
    FROM vw_order_facts
    WHERE is_valid_sale AND items_revenue > 0
),
top_item AS MATERIALIZED (   -- category of the most expensive item in the order
    SELECT DISTINCT ON (order_id) order_id, category
    FROM vw_item_facts
    ORDER BY order_id, price DESC, order_item_id
),
f AS (SELECT * FROM seq WHERE n = 1),
s AS (SELECT * FROM seq WHERE n = 2)
SELECT
    f.customer_unique_id,
    f.ts                                    AS first_order_at,
    t.category                              AS first_category,
    f.items_revenue                         AS first_order_value,
    f.n_items                               AS first_n_items,
    f.main_payment_type                     AS first_payment_type,
    f.max_installments                      AS first_installments,
    f.customer_state                        AS state,
    f.review_score                          AS first_review_score,
    f.is_late                               AS first_is_late,
    f.is_delivered                          AS first_is_delivered,
    s.ts                                    AS second_order_at,
    EXTRACT(EPOCH FROM (s.ts - f.ts)) / 86400 AS days_to_second
FROM f
JOIN top_item t USING (order_id)
LEFT JOIN s USING (customer_unique_id);

-- 8.1 Repeat rate (2nd order >24h later, within 180 days) by first-purchase category
-- Population: first order <= 2018-02-28, so every customer has 180 days of follow-up.
SELECT
    first_category,
    COUNT(*)                                                         AS customers,
    COUNT(*) FILTER (WHERE days_to_second > 1 AND days_to_second <= 180) AS repeaters,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second > 1 AND days_to_second <= 180) / COUNT(*), 2)
                                                                     AS repeat_pct
FROM vw_first_order_profile
WHERE first_order_at <= TIMESTAMP '2018-02-28'
GROUP BY first_category
HAVING COUNT(*) >= 1000
ORDER BY repeat_pct DESC;

-- 8.2 Same question by first-order value band and by payment type
-- NB: days_to_second is NULL for one-time buyers, so COALESCE to FALSE before AVG
--     (AVG ignores NULLs and would otherwise average over repeaters only).
SELECT
    CASE WHEN first_order_value < 50  THEN '1. <R$50'
         WHEN first_order_value < 100 THEN '2. R$50-100'
         WHEN first_order_value < 200 THEN '3. R$100-200'
         ELSE                              '4. R$200+' END            AS first_order_band,
    COUNT(*)                                                          AS customers,
    ROUND(100.0 * AVG(COALESCE(days_to_second > 1 AND days_to_second <= 180, FALSE)::INT), 2) AS repeat_pct
FROM vw_first_order_profile
WHERE first_order_at <= TIMESTAMP '2018-02-28'
GROUP BY 1
ORDER BY 1;

SELECT
    first_payment_type,
    COUNT(*)                                                          AS customers,
    ROUND(100.0 * AVG(COALESCE(days_to_second > 1 AND days_to_second <= 180, FALSE)::INT), 2) AS repeat_pct
FROM vw_first_order_profile
WHERE first_order_at <= TIMESTAMP '2018-02-28' AND first_payment_type IS NOT NULL
GROUP BY first_payment_type
ORDER BY customers DESC;
