# Portfolio notes (CV, LinkedIn, interview)

## CV bullets (pick 3 or 4)

- Built an end-to-end analytics pipeline on 100,000 real e-commerce orders (Python, PostgreSQL, Power BI): automated cleaning with 20 validation checks, a relational schema with enforced keys, and a one-command reproducible build with unit tests.
- Wrote advanced SQL (CTEs, window functions, `PERCENTILE_CONT`, cohort analysis) and showed that late deliveries cut the average review from 4.29 to 2.57, with satisfaction collapsing beyond 3 days late.
- Found and fixed a 4.5% revenue overstatement caused by join fan-out, and documented 30+ analytical decisions with the evidence behind each.
- Segmented 95,000 customers (RFM, K-means cross-check) and showed that 97% never reorder; sized the retention opportunity (under 1% of revenue even if doubled) to redirect priorities toward delivery reliability and acquisition.

## 60-second story

"I analysed about 100,000 orders from a Brazilian marketplace. The headline: revenue doubled year on year but has been flat since early 2018, and the clearest controllable problem is delivery. Late orders average 2.57 stars against 4.29, and it falls off a cliff past three days late, mostly in the north-east and at demand peaks. I also showed that 97% of customers never reorder and that this barely depends on the category or the first experience, so I sized a win-back campaign and found it would add under 1% of revenue. That pushed my recommendation toward fixing delivery and measuring acquisition. Along the way I found that joining tables naively inflated revenue by 4.5%, so I built the analysis on aggregated views and reconciled everything to the cent."

## Questions to prepare for

| Question | Short answer, grounded in the project |
|---|---|
| Why not use `customer_id`? | Olist generates a new one per order. `customer_unique_id` is the person, and using the wrong one makes almost everyone look like a one-time buyer. |
| How did you avoid double counting? | Items, payments and reviews are one-to-many per order. I aggregated each to one row per order before joining, and a naive join measurably inflated revenue by 4.5%. |
| How do you know your numbers are right? | Python validation (20 checks), SQL reconciliation, and a pipeline step that fails if the database stops tying out to the cleaning step. Revenue matches to the cent. |
| Does late delivery cause bad reviews? | The data shows a strong association (2.57 vs 4.29, a sharp cliff past 3 days). It is observational, so late orders may also be harder shipments. An A/B test on delivery estimates would establish cause. |
| What went wrong along the way? | A validation check used float comparison and reported 99.6% instead of 99.69%. A query averaged over repeaters only and showed 45% instead of 1.9%, which I caught because the number was implausible. A view took 2 minutes until I forced CTE materialization. All are in the decisions log. |
| What would you do next? | Add acquisition channel and cost data, run a holdout test on delivery estimates in the north-east, and track a leading indicator (orders not handed to the carrier within 2 days). |
| What are the limits? | No cost or marketing data, observational only, delivery times in the last two months are optimistic, and the sizing numbers are scenarios, not forecasts. |

## LinkedIn post draft

I analysed 100,000 real e-commerce orders end to end (SQL, Python, Power BI). Three things stood out:
1. Late delivery is the strongest driver of unhappy customers: 2.57 stars vs 4.29, and the damage starts at about 3 days late.
2. 97% of customers never buy again, and a better first experience barely changes that.
3. A naive SQL join inflated revenue by 4.5%. Always check your grain.
Code, SQL, decisions log and a 7-page report are on GitHub: <link>
