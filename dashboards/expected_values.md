# Expected values (reconcile your dashboard against these)

All values come from the PostgreSQL model (`SELECT * FROM olist_bi.kpi_reference;` returns the first table live). They apply with the report-level filters from BUILD_GUIDE step 4 (analysis window Jan 2017 to Aug 2018). If a card disagrees, fix it before building more visuals.

## Executive cards (Jan 2017 to Aug 2018, valid sales)

| Card | Expected |
|---|---|
| Orders | 97,910 |
| Revenue | R$13,449,530 (R$13,449,529.68) |
| AOV | R$137.37 |
| Customers | 94,707 |
| Delivered orders | 96,203 |
| Median delivery days | 10.21 |
| Late rate | 8.13% |
| Avg review | 4.117 (4.12) |
| Low review % (1-2 stars) | 13.85% |
| Repeat rate (all time, `dim_customer`) | 3.04% |

## Revenue page

| Check | Expected |
|---|---|
| Jan 2017 revenue / orders | R$120,098 / 787 |
| Nov 2017 revenue / orders | R$1,003,862 / 7,423 (peak) |
| Apr 2018 revenue | R$993,593 |
| Aug 2018 revenue / orders | R$848,860 / 6,421 |
| Top state | SP: R$5,150,779 (38.3%), then RJ R$1,802,436 (13.4%), MG R$1,568,856 (11.7%) |

## Categories

| Rank | Category | Revenue | Share |
|---|---|---|---|
| 1 | health_beauty | R$1,251,146 | 9.30% |
| 2 | watches_gifts | R$1,194,825 | 8.88% |
| 3 | bed_bath_table | R$1,035,485 | 7.70% |
| 4 | sports_leisure | R$977,729 | 7.27% |
| 5 | computers_accessories | R$902,923 | 6.71% |

## Delivery and reviews

| Check | Expected |
|---|---|
| Late rate Nov 2017 / Feb 2018 / Mar 2018 | 14.31% / 15.99% / 21.36% |
| State median days / late rate | SP 7.2 / 5.9%, RJ 12.0 / 13.5%, AL 22.3 / 24.0% |
| Avg review by delay bucket | 7+ days early 4.32, 0-7 days early 4.20, 1-3 days late 3.77, 3-7 days late 2.32, 7+ days late 1.73 |
| Avg review late vs on time | 2.57 vs 4.29 |

## Customers (all-time snapshot, `dim_customer`)

| Segment | Customers | Lifetime revenue |
|---|---|---|
| New big spenders | 14,727 | R$3,946,668 |
| At-risk big spenders | 14,015 | R$3,896,199 |
| Lost / low value | 34,267 | R$1,909,354 |
| Mid-age big spenders | 7,059 | R$1,766,159 |
| Recent small buyers | 22,028 | R$1,225,553 |
| Loyal repeaters | 1,856 | R$494,718 |
| Lapsed repeaters | 1,030 | R$255,460 |
| No valid purchase | 1,113 | R$0 |
| After snapshot date | 1 | R$290 |

## Cohorts

| Check | Expected |
|---|---|
| Cohort 2017-06: size / month 1 / month 3 | 3,102 / 14 customers (0.45%) / 12 customers (0.39%) |
| Weighted retention, month 1 (cohorts to Feb 2018) | about 0.5% |
