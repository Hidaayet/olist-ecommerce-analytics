# DAX measures

Create a blank table called `_Measures` (Home > Enter data > name it `_Measures` > Load), then add each measure below with **Modeling > New measure**. Move them to the `_Measures` table and hide its empty column.

> **Status:** these measures are written against the model in `sql/05_powerbi_model.sql` and use standard DAX patterns, but I could not run Power BI Desktop to test them. Reconcile every card against `dashboards/expected_values.md` as you build. If a number is off, the cause is almost always a missing report-level filter (see BUILD_GUIDE, step 4).

Table names: `fact_orders`, `fact_order_items`, `fact_cohort_retention`, `dim_date`, `dim_customer`, `dim_product`, `dim_state`.

## 1. Core sales

```dax
Orders =
CALCULATE ( COUNTROWS ( fact_orders ), fact_orders[is_valid_sale] = TRUE () )
```
```dax
Revenue =
CALCULATE ( SUM ( fact_orders[items_revenue] ), fact_orders[is_valid_sale] = TRUE () )
```
Format: Currency, 0 decimals, prefix `R$`. Revenue means item prices only, excluding freight.

```dax
Freight =
CALCULATE ( SUM ( fact_orders[freight_revenue] ), fact_orders[is_valid_sale] = TRUE () )
```
```dax
AOV =
DIVIDE ( [Revenue], [Orders] )
```
```dax
Customers =
CALCULATE ( DISTINCTCOUNT ( fact_orders[customer_unique_id] ), fact_orders[is_valid_sale] = TRUE () )
```
Counts real people (`customer_unique_id`), never `customer_id`.

```dax
Items per Order =
DIVIDE (
    CALCULATE ( SUM ( fact_orders[n_items] ), fact_orders[is_valid_sale] = TRUE () ),
    [Orders]
)
```

## 2. Time intelligence

`dim_date` must be marked as a date table (Table tools > Mark as date table > `date_key`).

```dax
Revenue PM =
CALCULATE ( [Revenue], DATEADD ( dim_date[date_key], -1, MONTH ) )
```
```dax
Revenue MoM % =
DIVIDE ( [Revenue] - [Revenue PM], [Revenue PM] )
```
```dax
Revenue LY =
CALCULATE ( [Revenue], SAMEPERIODLASTYEAR ( dim_date[date_key] ) )
```
```dax
Revenue YoY % =
DIVIDE ( [Revenue] - [Revenue LY], [Revenue LY] )
```
```dax
Revenue 3M Avg =
VAR _window =
    DATESINPERIOD ( dim_date[date_key], MAX ( dim_date[date_key] ), -3, MONTH )
VAR _months =
    CALCULATE ( DISTINCTCOUNT ( dim_date[month_start] ), _window )
RETURN
    IF ( _months = 3, CALCULATE ( DIVIDE ( [Revenue], 3 ), _window ) )
```
Returns blank for the first two months, where a full 3-month window does not exist. This relies on the report-level filter `dim_date[in_analysis_window] = TRUE`.

```dax
Revenue Cumulative =
CALCULATE ( [Revenue], FILTER ( ALL ( dim_date ), dim_date[date_key] <= MAX ( dim_date[date_key] ) ) )
```

## 3. Categories (Pareto)

```dax
Category Revenue =
CALCULATE ( SUM ( fact_order_items[price] ), fact_order_items[is_valid_sale] = TRUE () )
```
```dax
Items Sold =
CALCULATE ( COUNTROWS ( fact_order_items ), fact_order_items[is_valid_sale] = TRUE () )
```
```dax
Category Share % =
DIVIDE ( [Category Revenue], CALCULATE ( [Category Revenue], ALL ( dim_product[category] ) ) )
```
```dax
Category Cumulative % =
VAR _current = [Category Revenue]
VAR _all = ALL ( dim_product[category] )
RETURN
    DIVIDE (
        SUMX ( FILTER ( _all, [Category Revenue] >= _current ), [Category Revenue] ),
        CALCULATE ( [Category Revenue], _all )
    )
```
Use on a combo chart: columns = `Category Revenue`, line = `Category Cumulative %`, axis = `dim_product[category]` sorted by `Category Revenue` descending (Top N filter, 15).

## 4. Delivery

```dax
Delivered Orders =
CALCULATE ( COUNTROWS ( fact_orders ), fact_orders[is_delivered] = TRUE () )
```
```dax
Avg Delivery Days =
CALCULATE ( AVERAGE ( fact_orders[delivery_days] ), fact_orders[is_delivered] = TRUE () )
```
```dax
Median Delivery Days =
CALCULATE ( MEDIAN ( fact_orders[delivery_days] ), fact_orders[is_delivered] = TRUE () )
```
```dax
P90 Delivery Days =
CALCULATE ( PERCENTILE.INC ( fact_orders[delivery_days], 0.9 ), fact_orders[is_delivered] = TRUE () )
```
```dax
Avg Promised Days =
CALCULATE ( AVERAGE ( fact_orders[estimated_days] ), fact_orders[is_delivered] = TRUE () )
```
```dax
Late Orders =
CALCULATE ( COUNTROWS ( fact_orders ), fact_orders[is_delivered] = TRUE (), fact_orders[is_late] = TRUE () )
```
```dax
Late Rate =
DIVIDE ( [Late Orders], [Delivered Orders] )
```
Format as percentage, 1 decimal.

```dax
Avg Days Late (when late) =
CALCULATE ( AVERAGE ( fact_orders[delay_days] ), fact_orders[is_late] = TRUE () )
```

## 5. Reviews

> **DAX gotcha:** a blank compares as 0, so `review_score <= 2` would wrongly include orders with no review. Always use `IN { 1, 2 }` or a lower bound too.

```dax
Reviewed Orders =
CALCULATE ( COUNTROWS ( fact_orders ), fact_orders[is_valid_sale] = TRUE (), fact_orders[review_score] <> BLANK () )
```
```dax
Avg Review =
CALCULATE ( AVERAGE ( fact_orders[review_score] ), fact_orders[is_valid_sale] = TRUE () )
```
```dax
Low Review % =
DIVIDE (
    CALCULATE ( COUNTROWS ( fact_orders ), fact_orders[is_valid_sale] = TRUE (), fact_orders[review_score] IN { 1, 2 } ),
    [Reviewed Orders]
)
```
```dax
Avg Review (Late) =
CALCULATE ( [Avg Review], fact_orders[is_delivered] = TRUE (), fact_orders[is_late] = TRUE () )
```
```dax
Avg Review (On time) =
CALCULATE ( [Avg Review], fact_orders[is_delivered] = TRUE (), fact_orders[is_late] = FALSE () )
```

## 6. Customers and segments

`dim_customer` is an **all-time snapshot**: it has no relationship to `dim_date`, so date slicers do not filter these measures. Say so in a text box on the page.

```dax
Customer Count =
DISTINCTCOUNT ( dim_customer[customer_unique_id] )
```
```dax
Segment Revenue =
SUM ( dim_customer[lifetime_revenue] )
```
```dax
Segment Customers % =
DIVIDE ( [Customer Count], CALCULATE ( [Customer Count], ALL ( dim_customer[segment] ) ) )
```
```dax
Segment Revenue % =
DIVIDE ( [Segment Revenue], CALCULATE ( [Segment Revenue], ALL ( dim_customer[segment] ) ) )
```
```dax
Repeat Customers =
CALCULATE ( COUNTROWS ( dim_customer ), dim_customer[is_repeat_customer] = TRUE () )
```
```dax
Repeat Rate =
DIVIDE ( [Repeat Customers], CALCULATE ( COUNTROWS ( dim_customer ), dim_customer[valid_orders] >= 1 ) )
```

## 7. Cohort retention

`fact_cohort_retention` has no relationships. Use `cohort` on rows and `month_index` on columns of a matrix.

```dax
Retained Customers =
SUM ( fact_cohort_retention[active_customers] )
```
```dax
Cohort Customers =
SUMX ( VALUES ( fact_cohort_retention[cohort] ), CALCULATE ( MAX ( fact_cohort_retention[cohort_size] ) ) )
```
```dax
Retention % =
DIVIDE ( [Retained Customers], [Cohort Customers] )
```
Filter the matrix to `month_index` 1 to 6 and cohorts up to 2018-02 (the cohorts with six months of follow-up). Format as percentage, 2 decimals, with conditional formatting (background, white to dark blue).
