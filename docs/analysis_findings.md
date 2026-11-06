# Analysis findings (Phase 3, SQL)

Every number below comes from a query in `sql/03_analysis/`. Revenue = `SUM(price)` on valid sales (not canceled or unavailable), excluding freight. Unless stated, the window is **Jan 2017 to Aug 2018**. Findings are facts from the data. Interpretations are labelled as such.

## Q1. How does revenue evolve over time? (`01_revenue_trends.sql`)

- **Growth came from volume, not basket size.** Jan-Aug 2018 revenue was R$7.34M against R$3.08M for Jan-Aug 2017 (**+138%**). Orders grew from 22,562 to 53,531 while average order value stayed flat (R$136.55 vs R$137.14) and items per order stayed at about 1.1.
- **Growth stalled in 2018.** Monthly revenue peaked at R$1.00M in Nov 2017 (+52% month over month, which coincides with Black Friday), then settled between R$838k and R$994k. Aug 2018 (R$849k) is about 15% below Apr 2018 (R$994k).
- **Geographic concentration.** SP generates 38.3% of revenue, and SP + RJ + MG together 63.4%.
- **Timing.** Monday is the busiest day (16.3% of orders) and Saturday the quietest (11.0%). Order volume peaks between 11:00 and 16:00, with a second peak at 21:00.
- **Payments.** Credit card is the main method for 75.5% of orders (3.6 instalments on average), boleto 19.9%.

## Q2. Which categories contribute most? (`02_category_pareto.sql`)

- **8 of 74 categories make up 50% of revenue, and 18 make up 80%.** The top five are health_beauty (9.3%, R$1.25M), watches_gifts (8.9%), bed_bath_table (7.7%), sports_leisure (7.3%) and computers_accessories (6.7%).
- **Fastest absolute growth, Jan-Aug 2017 vs 2018:** health_beauty +R$523k (+211%) and watches_gifts +R$502k (+243%). Slowest among categories with a meaningful base: garden_tools (+49%) and perfumery (+43%).
- **Quality varies.** office_furniture has the lowest average review (3.50, with 26.0% of reviews at 1-2 stars). bed_bath_table is the third-largest category yet scores only 3.90 (18.8% at 1-2 stars).
- **Freight is a heavy burden in some categories**: construction tools (37% of item price), auto (33%) and office_furniture (27%).

## Q3. What are the delivery performance patterns? (`03_delivery_kpis.sql`)

- **Typical delivery is 10.2 days (median), 23.1 days at P90.** Olist promises 23.6 days on average, so on-time orders arrive about 13 days early. **8.1% of orders arrive late**, by 9.5 days on average.
- **The carrier leg is the bottleneck.** Median stage times are 0.01 days for approval, 1.81 days from approval to carrier handover, and 7.10 days from carrier to customer (about 80% of the total).
- **Lateness comes in waves**, not at a constant rate: Nov 2017 (14.3%), Feb 2018 (16.0%) and Mar 2018 (21.4%), against 3-5% in calm months.
- **Geography drives speed.** Median delivery is 7.2 days in SP but 22.3 in AL (24.0% late), 21.1 in PA and 19.2 in MA (19.6% late). Cross-state orders take a median of 12.8 days against 6.6 for same-state, are late 9.4% of the time against 6.1%, and carry 34.8% freight against 23.8%.
- **Caveat (D-20):** the Jul-Aug 2018 medians look much faster (7.5 and 7.0 days) partly because slow orders had not yet arrived when the data was captured.

## Q4. How do delays relate to reviews? (`04_delay_vs_reviews.sql`)

- **Late delivery is the strongest signal in the dataset.** Average review is 4.29 for on-time orders and **2.57 for late ones**. 1-2 star reviews are 9.2% of on-time orders and **54.1% of late ones**.
- **There is a cliff around 3 days.** Average score is 3.77 at 1-3 days late, 2.32 at 3-7 days late and about 1.7 beyond 7 days. A 1-3 day delay is a mild annoyance, while a week is a broken promise.
- **38.0% of all 1-star reviews follow a late delivery**, though only 8.0% of orders are late.
- **The promise matters beyond the wait itself.** In the 21-30 day band, on-time orders score 3.96 and late ones 2.84. Waiting also lowers scores on its own: on-time orders average 4.42 under 7 days and 3.67 beyond 30.
- Late customers also write more: 58-66% leave a comment against 37-41% of on-time customers.
- Correlation of review score with delay is -0.27, and with delivery days -0.33. **This is association, not proof of cause:** late orders also tend to be harder shipments.

## Q5. Which customers generate the most value? (`06_customer_value.sql`, all-time)

- **Revenue is concentrated but not extreme.** The top 10% of customers generate 41.1% of revenue, the top 1% generate 11.5% and the top 20% generate 56.9%.
- **Premium customers (R$500+ lifetime) are 3.9% of customers and 25.7% of revenue.** Low spenders (under R$100) are 57.2% of customers but 21.5% of revenue.
- **High-value orders look different**: 1.33 items per order against 1.10, 4.8 instalments against 2.5, and 80.9% paid by credit card against 74.3%.
- SP has the lowest revenue per customer (R$129.9) against R$148.0 in RJ, R$156.4 in BA and R$163.9 in PE.

## Q6. How does behaviour evolve across cohorts? (`05_cohorts_retention.sql`)

- **97.0% of customers buy once.** 2.8% buy twice and 0.25% three or more times. Repeat customers are 3.0% of customers but 5.6% of revenue.
- **Retention is tiny at every age.** Weighted across cohorts: 0.48% return in month 1, 0.26% in month 3 and 0.23% in month 6. There is no visible improvement or decay trend across the 2017-2018 cohorts.
- **When repeat buyers return:** the median gap is 28 days and the P75 is 125 days. **31.0% of second orders happen within 24 hours**, which looks like split baskets, not loyalty.
- **A bad first experience barely changes repeat behaviour.** 180-day repeat rates are 3.21% after a 1-star first order and 3.27% after a 5-star one. A late first delivery gives 2.70% against 3.18% on time.
- Repeat rates by state run from 1.69% (CE) to 3.38% (RJ).
- **Interpretation (untested hypotheses):** retention looks structural, not service-driven. Candidates are one-off purchase categories (furniture, appliances), no loyalty mechanism, or customers identified under several IDs. Phase 4 will test the first one.

## Data quality follow-ups (`07_data_quality_investigations.sql`)

- **Payment gaps (303 orders, 0.31%).** 264 customers paid more than items+freight (average +R$11.63), and the share rises with instalments from 0.01% at 1 instalment to 0.86% at 7 or more, consistent with instalment interest. 39 paid less (average -R$5.10).
- **Timestamp anomalies (189 orders).** 166 were handed to the carrier before purchase and 23 were delivered before carrier handover. 158 of the 189 fall in May-Aug 2018 and no seller stands out, which suggests a recent logging change. They are 0.2% of delivered orders, so the impact is negligible.

## Implications to carry into the executive report

1. Growth depends on acquiring new customers, because retention is near zero whatever the service quality. Marketing efficiency matters more than loyalty tactics here.
2. Late delivery is the clearest lever on customer satisfaction, and the damage starts at about 3 days late. Promising realistic dates in slow regions (north and north-east) may protect reviews at a small cost in conversion.
3. Peak events (Nov 2017, Feb-Mar 2018) overwhelmed the carrier network. Capacity planning should come before the next peak.
4. Revenue is plateauing at about R$0.9M per month, so category mix and customer acquisition cost deserve attention next.
