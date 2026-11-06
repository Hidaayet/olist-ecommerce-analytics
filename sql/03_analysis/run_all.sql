-- Runs every analysis file in order. From the REPO ROOT:
--     psql -d olist -f sql/03_analysis/run_all.sql
\i sql/03_analysis/00_base_views.sql
\i sql/03_analysis/01_revenue_trends.sql
\i sql/03_analysis/02_category_pareto.sql
\i sql/03_analysis/03_delivery_kpis.sql
\i sql/03_analysis/04_delay_vs_reviews.sql
\i sql/03_analysis/05_cohorts_retention.sql
\i sql/03_analysis/06_customer_value.sql
\i sql/03_analysis/07_data_quality_investigations.sql
\i sql/03_analysis/08_first_purchase_drivers.sql
