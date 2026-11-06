-- =============================================================================
-- 04_validation.sql  |  Post-load reconciliation: does the database tell the
-- same story as the Python cleaning log? Every check returns pass = TRUE/FALSE.
-- Run: psql -d olist -f sql/04_validation.sql
-- =============================================================================
SET search_path TO olist;

WITH checks AS (
    SELECT 'orders row count = 99,441' AS check_name,
           (SELECT COUNT(*) FROM orders) = 99441 AS pass,
           (SELECT COUNT(*) FROM orders)::TEXT AS value
  UNION ALL
    SELECT 'vw_order_facts has exactly 1 row per order (no fan-out)',
           (SELECT COUNT(*) FROM vw_order_facts) = (SELECT COUNT(*) FROM orders),
           (SELECT COUNT(*) FROM vw_order_facts)::TEXT
  UNION ALL
    SELECT 'sum of items_revenue in view = sum(price) in order_items',
           (SELECT SUM(items_revenue) FROM vw_order_facts) = (SELECT SUM(price) FROM order_items),
           (SELECT SUM(items_revenue) FROM vw_order_facts)::TEXT
  UNION ALL
    SELECT 'sum(price) = 13,591,643.70 (matches Python)',
           (SELECT SUM(price) FROM order_items) = 13591643.70,
           (SELECT SUM(price) FROM order_items)::TEXT
  UNION ALL
    SELECT 'payments total in view = sum(payment_value)',
           (SELECT SUM(payment_total) FROM vw_order_facts) = (SELECT SUM(payment_value) FROM order_payments),
           (SELECT SUM(payment_total) FROM vw_order_facts)::TEXT
  UNION ALL
    SELECT 'vw_item_facts has exactly 1 row per order item',
           (SELECT COUNT(*) FROM vw_item_facts) = (SELECT COUNT(*) FROM order_items),
           (SELECT COUNT(*) FROM vw_item_facts)::TEXT
  UNION ALL
    SELECT 'distinct real customers = 96,096',
           (SELECT COUNT(DISTINCT customer_unique_id) FROM customers) = 96096,
           (SELECT COUNT(DISTINCT customer_unique_id) FROM customers)::TEXT
  UNION ALL
    SELECT 'late deliveries = 7,826',
           (SELECT COUNT(*) FROM orders WHERE is_late) = 7826,
           (SELECT COUNT(*) FROM orders WHERE is_late)::TEXT
  UNION ALL
    SELECT 'valid sales = 98,207 (99,441 - 1,234)',
           (SELECT COUNT(*) FROM orders WHERE is_valid_sale) = 98207,
           (SELECT COUNT(*) FROM orders WHERE is_valid_sale)::TEXT
)
SELECT check_name, pass, value FROM checks;

-- The fan-out trap, shown live: same question, wrong vs right answer
SELECT 'WRONG: naive items x payments join' AS method,
       ROUND(SUM(oi.price), 2) AS total_price
FROM order_items oi JOIN order_payments op USING (order_id)
UNION ALL
SELECT 'RIGHT: aggregate first (vw_order_facts)',
       ROUND(SUM(items_revenue), 2)
FROM vw_order_facts;
