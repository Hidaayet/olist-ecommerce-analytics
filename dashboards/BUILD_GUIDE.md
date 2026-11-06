# Power BI build guide

About 60 to 90 minutes. Power BI Desktop runs on Windows only. All data preparation is already done in PostgreSQL (schema `olist_bi`), so the report only needs relationships, measures and visuals.

**Before you start:** the pipeline has run (`python -m src.run_pipeline`), so `olist_bi` exists. Check with `SELECT * FROM olist_bi.kpi_reference;` in pgAdmin.

## 1. Connect to PostgreSQL

1. **Home > Get data > PostgreSQL database.**
2. Server: `localhost:5432` (use your port if different). Database: `olist`. Mode: **Import**.
3. Credentials, **Database** tab: user `postgres` and your password.
4. In the Navigator, expand the `olist_bi` schema and tick: `dim_date`, `dim_state`, `dim_customer`, `dim_product`, `dim_seller`, `fact_orders`, `fact_order_items`, `fact_cohort_retention`, `kpi_reference`. Click **Load**.

If Power BI asks for the Npgsql provider, install it from the link in the dialog, then restart Power BI.

## 2. Data types and sorting

In **Table view**, check and set:

| Table | Column | Setting |
|---|---|---|
| dim_date | date_key | Date. **Table tools > Mark as date table** > `date_key` |
| dim_date | month_name | Sort by column: `month_num` |
| dim_date | weekday_name | Sort by column: `iso_weekday_num` |
| fact_orders | order_date | Date |
| fact_orders | items_revenue, freight_revenue, payment_total | Fixed decimal number |
| fact_cohort_retention | cohort_month | Date |
| fact_cohort_retention | retention_pct | Decimal number |

## 3. Model: relationships

Open **Model view** and create these, all **many-to-one, single direction** (from the dimension to the fact):

| From (one side) | To (many side) |
|---|---|
| dim_date[date_key] | fact_orders[order_date] |
| dim_date[date_key] | fact_order_items[order_date] |
| dim_customer[customer_unique_id] | fact_orders[customer_unique_id] |
| dim_state[state_code] | fact_orders[customer_state] |
| dim_state[state_code] | fact_order_items[customer_state] |
| dim_product[product_id] | fact_order_items[product_id] |
| dim_seller[seller_id] | fact_order_items[seller_id] |

Do **not** relate the two fact tables to each other, and do **not** relate `dim_state` to `dim_customer` (both would create ambiguous paths). `fact_cohort_retention` and `kpi_reference` stay unrelated.

Then: create the `_Measures` table and add every measure from `dax_measures.md`. Hide the foreign-key columns (`order_date`, `customer_unique_id`, `customer_state`, `product_id`, `seller_id` in the fact tables) so report authors use the dimensions.

## 4. Report-level filters (do this once, it fixes most wrong numbers)

On any page, open the **Filters** pane and drag into **Filters on all pages**:

- `dim_date[in_analysis_window]` = **TRUE** (Jan 2017 to Aug 2018; the edge months are sparse)

Revenue and order measures already exclude canceled and unavailable orders (`is_valid_sale`), and delivery measures use delivered orders only.

## 5. Theme and canvas

**View > Themes > Browse for themes** > `dashboards/olist_theme.json`. Use 16:9 pages. Place slicers in a thin strip across the top; keep one message per page, and put a short insight in a text box titled **"So what"**.

## 6. Pages

### Page 1: Executive summary
- **Cards (6):** Revenue, Orders, AOV, Customers, Late Rate, Avg Review.
- **Line and clustered column chart:** axis `dim_date[year_month]`; columns `Revenue`; line `Revenue 3M Avg`.
- **Filled map or bar chart:** `dim_state[state_name]` with `Revenue`. Set the map location to Brazil if needed.
- **Bar chart:** top 10 `dim_product[category]` by `Category Revenue`.
- **Slicers:** `dim_date[year]`, `dim_state[region]`.
- **"So what" text box:** *Revenue more than doubled year on year but has plateaued near R$0.9M a month since January 2018. Late deliveries (8.1%) are the strongest driver of poor reviews.*

### Page 2: Revenue and categories
- **Column chart:** `year_month` with `Revenue`; tooltip `Revenue MoM %`, `Revenue YoY %`.
- **Combo (Pareto):** axis `dim_product[category]` (Top N = 15 by `Category Revenue`), columns `Category Revenue`, line `Category Cumulative %`.
- **Table:** category, `Items Sold`, `Category Revenue`, `Category Share %`.
- **Column chart:** `dim_date[weekday_name]` with `Orders` (Monday busiest, Saturday quietest).
- **Slicer:** `dim_state[state_name]`.

### Page 3: Delivery performance
- **Cards:** Median Delivery Days, P90 Delivery Days, Avg Promised Days, Late Rate.
- **Line chart:** `year_month` with `Late Rate` (spikes in Nov 2017, Feb to Mar 2018).
- **Bar chart:** `dim_state[state_code]` with `Median Delivery Days`, sorted descending.
- **Scatter:** details `dim_state[state_code]`, X `Median Delivery Days`, Y `Late Rate`, size `Delivered Orders`.
- **Slicers:** `dim_state[region]`, `dim_date[year]`.

### Page 4: Delays and reviews
- **Clustered column:** axis `fact_orders[delay_bucket]` with `Avg Review`. This is the key chart: the cliff after 3 days late.
- **Cards:** `Avg Review (On time)` and `Avg Review (Late)`, side by side (4.29 vs 2.57).
- **Column chart:** `fact_orders[delivery_outcome]` with `Low Review %`.
- **Bar chart:** `dim_state[state_code]` with `Avg Review`.
- **Optional:** Decomposition tree on `Reviewed Orders` split by `delivery_outcome`, `region`, `category`.

### Page 5: Customers
- **Clustered bar:** axis `dim_customer[segment]` with `Segment Customers %` and `Segment Revenue %`.
- **Table or matrix:** segment, `Customer Count`, `Segment Revenue`, `Segment Revenue %`.
- **Cards:** `Repeat Rate`, `Customer Count`.
- **Text box (required):** *All-time snapshot: date slicers do not filter this page's customer measures.*
- **Slicer:** `dim_customer[segment]`.

### Page 6: Cohort retention
- **Matrix:** rows `fact_cohort_retention[cohort]`, columns `month_index`, values `Retention %`. Filter `month_index` to 1 to 6 and cohorts to 2018-02 or earlier. Conditional formatting: background, white to dark blue.
- **Line chart:** axis `month_index`, values `Retention %`: the flat, very low curve.
- **"So what" text box:** *Fewer than 1% of customers return in any month after their first order. Growth depends on acquiring new customers.*

## 7. Check your work

Compare every card and a few chart tooltips against `dashboards/expected_values.md`. If revenue is far too large, the `is_valid_sale` filter is missing; if counts are too high, the report-level `in_analysis_window` filter is missing.

## 8. Save, export, share

1. Save as `dashboards/olist_dashboard.pbix` on your machine.
2. **Do not commit the `.pbix`.** It embeds the dataset, which is licensed CC BY-NC-SA 4.0. Instead commit:
   - a **template** with no data: **File > Export > Power BI template** > `dashboards/olist_dashboard.pbit`
   - **screenshots** of each page in `reports/dashboard_screenshots/` (use them in the README)
   - **File > Export > PDF** of the report (optional)
3. To refresh after re-running the pipeline: **Home > Refresh**.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Cannot connect | PostgreSQL service running? Right port? See `docs/RUN_GUIDE.md`, troubleshooting |
| `olist_bi` not listed | Run `python -m src.run_pipeline`, then **Refresh** in the Navigator |
| Relationship warns about ambiguity | You related the two fact tables, or `dim_state` to `dim_customer`. Delete those |
| Revenue includes canceled orders | The measure must filter `is_valid_sale = TRUE` (see `dax_measures.md`) |
| Date slicer does nothing on Page 5 | Expected: `dim_customer` has no date relationship |
| `Retention %` totals look odd | Filter `month_index` to 1 to 6 before reading totals |
