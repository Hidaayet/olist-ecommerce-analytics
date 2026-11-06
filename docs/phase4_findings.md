# Phase 4 findings: segmentation and retention drivers

Source: `notebooks/04_segmentation.ipynb` (uses `src/segmentation.py` and `sql/03_analysis/08_first_purchase_drivers.sql`).
Measured results are separated from interpretations and suggested actions.

## Decisions

| ID | Decision | Why |
|---|---|---|
| D-22 | **RFM: quintiles for Recency and Monetary, a binary rule for Frequency** (1 vs 2+ orders). Snapshot date 2018-09-01 | 97% of customers have exactly 1 order, so frequency quintiles would be noise |
| D-23 | **"Repeat" = a 2nd order placed more than 24 hours and at most 180 days after the first**, for customers whose first order is on or before 2018-02-28 | 31% of second orders occur within a day (split baskets, not loyalty). This stricter rule gives a 1.89% repeat rate, replacing the 3.2% in `05_cohorts_retention.sql` (query 5.5), which counted same-day orders |
| D-24 | **`vw_first_order_profile` forces CTE materialization** (`AS MATERIALIZED`) | Without it the view ran for over 2 minutes. With it, 2 seconds |
| D-25 | **Bug found and fixed in query 8.2**: `AVG()` ignores NULLs, and one-time buyers have a NULL `days_to_second`, so the first version averaged over repeaters only (about 45% instead of 1.9%). Fixed with `COALESCE(..., FALSE)` | Always check that a rate lands in a plausible range before trusting it |

## Findings

**Segments (Q5).** 94,982 customers, R$13.49M lifetime revenue.

| Segment | Customers | % customers | % revenue |
|---|---|---|---|
| New big spenders | 14,727 | 15.5 | 29.2 |
| At-risk big spenders | 14,015 | 14.8 | 28.9 |
| Mid-age big spenders | 7,059 | 7.4 | 13.1 |
| Lost / low value | 34,267 | 36.1 | 14.1 |
| Recent small buyers | 22,028 | 23.2 | 9.1 |
| Loyal repeaters | 1,856 | 2.0 | 3.7 |
| Lapsed repeaters | 1,030 | 1.1 | 1.9 |

- The three big-spender segments are 38% of customers and 71% of revenue, and **all of them have bought only once**. Repeat buyers are 3% of customers and 6% of revenue.
- K-means adds no structure beyond the rules. With the repeat flag included, it recovers that flag exactly. Among one-time buyers, clusters differ by recency (median 277 vs 53 days) but not by spend (R$88 vs R$85), so spend tiers are a business choice, not a natural grouping.

**Retention drivers (Q6).** 56,319 customers have a full 180-day window. The overall repeat rate is **1.89%** (1,062 customers).

- **Month-by-month return** is small and flat: about 0.5% at month 1 falling to about 0.2% at month 6, with no clear difference between cohorts.
- **Category matters a little.** Repeat rates differ across the 18 categories with 1,000+ first-time customers (chi-square p = 2e-5): from 1.0% (cool_stuff) to 2.9% (fashion_bags_accessories). The "one-off categories" hypothesis is **not supported**, because bed_bath_table (2.5%), sports_leisure (2.6%) and furniture_decor sit above average.
- **First review score has a small gradient.** 5-star: 2.05% (95% CI 1.90-2.22). 1-star: 1.54% (1.26-1.88). A late first delivery gives 1.53% (1.20-1.95) against 1.92% (1.81-2.05), but those intervals overlap.
- **Order value shows no effect** (1.8-1.9% in all four bands), and neither does payment type.

**Correction to the Phase 3 write-up.** `analysis_findings.md` said a bad first experience "barely changes" repeat behaviour (3.21% vs 3.27%). That figure counted same-day second orders, which are unrelated to the experience. With the stricter definition (D-23) a small gradient appears (2.05% vs 1.54%). The conclusion that retention is mostly structural still holds, but "no effect" was too strong.

## Interpretation and suggested actions (hypotheses, not results)

1. Fixing delivery will improve reviews a lot (Phase 3) but is unlikely to lift retention much by itself, since even the best-reviewed customers reorder only about 2% of the time.
2. The largest pool of value is 14k at-risk big spenders (R$3.9M of past revenue). A win-back test with a **holdout control group** is the only way to learn whether any intervention can move a 2% baseline.
3. Low retention may reflect marketplace behaviour (one-off buying, no loyalty mechanism). The dataset has no marketing, pricing or competitor data, so this cannot be tested here.

## Limitations

Observational data only. Repeat rates are low, so subgroup estimates have wide intervals. Customer identity relies on `customer_unique_id`, which may miss customers who registered twice. RFM recency depends on the 2018-09-01 snapshot, so "lost" is relative to when the data ends.
