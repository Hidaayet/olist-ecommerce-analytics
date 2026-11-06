-- =============================================================================
-- 04_delay_vs_reviews.sql  |  Q4: How do delivery delays relate to reviews?
-- Population: delivered orders with a review, inside the analysis window.
-- Techniques: CASE bucketing, CORR, conditional aggregation, window shares.
-- delay_days = delivery - estimated date (positive = late).
-- =============================================================================
SET search_path TO olist;

-- 4.1 Review score by lateness bucket -----------------------------------------
WITH base AS (
    SELECT
        delay_days,
        delivery_days,
        review_score,
        review_has_comment,
        CASE
            WHEN delay_days <= -14 THEN '1. 14+ days early'
            WHEN delay_days <= -7  THEN '2. 7-14 days early'
            WHEN delay_days <= 0   THEN '3. 0-7 days early / on time'
            WHEN delay_days <= 3   THEN '4. 1-3 days late'
            WHEN delay_days <= 7   THEN '5. 3-7 days late'
            WHEN delay_days <= 14  THEN '6. 7-14 days late'
            ELSE                        '7. 14+ days late'
        END AS bucket
    FROM vw_order_facts
    WHERE is_delivered AND in_analysis_window AND review_score IS NOT NULL
)
SELECT
    bucket,
    COUNT(*)                                                    AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS share_pct,
    ROUND(AVG(review_score), 2)                                 AS avg_score,
    ROUND(100.0 * AVG((review_score = 1)::INT), 1)              AS pct_1_star,
    ROUND(100.0 * AVG((review_score = 5)::INT), 1)              AS pct_5_star,
    ROUND(100.0 * AVG(review_has_comment::INT), 1)              AS pct_with_comment
FROM base
GROUP BY bucket
ORDER BY bucket;

-- 4.2 Late vs not late, and the correlation ---------------------------------------
SELECT
    CASE WHEN is_late THEN 'late' ELSE 'on time / early' END    AS delivery,
    COUNT(*)                                                    AS orders,
    ROUND(AVG(review_score), 2)                                 AS avg_score,
    ROUND(100.0 * AVG((review_score <= 2)::INT), 1)             AS pct_1_2_star
FROM vw_order_facts
WHERE is_delivered AND in_analysis_window AND review_score IS NOT NULL
GROUP BY is_late
ORDER BY is_late;

SELECT
    ROUND(CORR(delay_days, review_score)::NUMERIC, 3)      AS corr_delay_vs_score,
    ROUND(CORR(delivery_days, review_score)::NUMERIC, 3)   AS corr_delivery_days_vs_score
FROM vw_order_facts
WHERE is_delivered AND in_analysis_window AND review_score IS NOT NULL;

-- 4.3 Is it the lateness or the absolute wait? ---------------------------------
-- Compare orders with a similar total wait, split by whether the promise was met.
SELECT
    CASE WHEN delivery_days < 7  THEN 'a. <7 days'
         WHEN delivery_days < 14 THEN 'b. 7-14 days'
         WHEN delivery_days < 21 THEN 'c. 14-21 days'
         WHEN delivery_days < 30 THEN 'd. 21-30 days'
         ELSE                         'e. 30+ days' END       AS actual_wait,
    COUNT(*) FILTER (WHERE NOT is_late)                       AS orders_on_time,
    ROUND(AVG(review_score) FILTER (WHERE NOT is_late), 2)    AS score_on_time,
    COUNT(*) FILTER (WHERE is_late)                           AS orders_late,
    ROUND(AVG(review_score) FILTER (WHERE is_late), 2)        AS score_late
FROM vw_order_facts
WHERE is_delivered AND in_analysis_window AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- 4.4 Share of all 1-star reviews that follow a late delivery -----------------
SELECT
    COUNT(*)                                                   AS one_star_reviews,
    ROUND(100.0 * AVG(is_late::INT), 1)                        AS pct_of_them_were_late,
    (SELECT ROUND(100.0 * AVG(is_late::INT), 1)
     FROM vw_order_facts
     WHERE is_delivered AND in_analysis_window AND review_score IS NOT NULL) AS baseline_late_pct
FROM vw_order_facts
WHERE is_delivered AND in_analysis_window AND review_score = 1;

-- 4.5 Score by customer state, next to late rate ---------------------------------
SELECT
    customer_state,
    COUNT(*)                                       AS reviewed_orders,
    ROUND(100.0 * AVG(is_late::INT), 1)            AS late_pct,
    ROUND(AVG(review_score), 2)                    AS avg_score
FROM vw_order_facts
WHERE is_delivered AND in_analysis_window AND review_score IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 500
ORDER BY avg_score
LIMIT 8;

-- 4.6 Do unhappy customers write more? Comment rate by score -------------------
SELECT
    review_score,
    COUNT(*)                                            AS reviews,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS share_pct,
    ROUND(100.0 * AVG(review_has_comment::INT), 1)      AS pct_with_comment
FROM vw_order_facts
WHERE in_analysis_window AND review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;
