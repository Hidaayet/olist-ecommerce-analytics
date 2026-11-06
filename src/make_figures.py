"""
Phase 6 - Generate every chart used in the executive report (reports/figures/*.png).

    python -m src.make_figures

Reads from the PostgreSQL views (needs the database built: python -m src.run_pipeline).
Revenue = SUM(price) on valid sales (not canceled/unavailable), window Jan 2017 - Aug 2018.
"""
from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

from src import segmentation as sg

FIG_DIR = Path(__file__).resolve().parent.parent / "reports" / "figures"
NAVY, LIGHT, ORANGE, RED, GREY = "#1f4e79", "#9db4d0", "#d9822b", "#b23b3b", "#8a8a8a"

plt.rcParams.update({
    "figure.dpi": 150, "savefig.dpi": 150, "savefig.bbox": "tight",
    "axes.spines.top": False, "axes.spines.right": False,
    "font.size": 10, "axes.titlesize": 12, "axes.titleweight": "bold",
})


def _save(name: str):
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    plt.savefig(FIG_DIR / name)
    plt.close()
    print(f"  saved {name}")


# ------------------------------------------------------------------ 1. revenue
def fig_revenue_trend(engine):
    df = pd.read_sql(
        """SELECT purchase_month AS month, SUM(items_revenue)::float AS revenue, COUNT(*) AS orders
           FROM olist.vw_order_facts WHERE is_valid_sale AND in_analysis_window
           GROUP BY 1 ORDER BY 1""", engine)
    df["month"] = pd.to_datetime(df["month"])
    df["roll"] = df["revenue"].rolling(3).mean()
    fig, ax = plt.subplots(figsize=(9, 4))
    ax.bar(df["month"], df["revenue"] / 1e3, width=22, color=LIGHT, label="Monthly revenue")
    ax.plot(df["month"], df["roll"] / 1e3, color=NAVY, lw=2.2, label="3-month average")
    peak = df.loc[df["revenue"].idxmax()]
    ax.set_ylim(0, df["revenue"].max() / 1e3 * 1.18)
    ax.annotate(f"Nov 2017 peak: R${peak.revenue/1e6:.2f}M", (peak["month"], peak.revenue / 1e3),
                xytext=(0, 8), textcoords="offset points", ha="center", fontsize=9, color=NAVY)
    ax.set_ylabel("Revenue (R$ thousand)"); ax.set_title("Revenue more than doubled year on year, then plateaued near R$0.9M a month")
    ax.legend(frameon=False, loc="upper left", bbox_to_anchor=(0.0, 0.95))
    _save("fig01_revenue_trend.png")


# ----------------------------------------------------------------- 2. categories
def fig_category_pareto(engine):
    df = pd.read_sql(
        """SELECT category, SUM(price)::float AS revenue FROM olist.vw_item_facts
           WHERE is_valid_sale AND in_analysis_window GROUP BY 1 ORDER BY 2 DESC""", engine)
    df["cum"] = 100 * df["revenue"].cumsum() / df["revenue"].sum()
    top = df.head(12)
    fig, ax = plt.subplots(figsize=(9, 4.3))
    ax.bar(range(len(top)), top["revenue"] / 1e6, color=NAVY)
    ax.set_xticks(range(len(top))); ax.set_xticklabels(top["category"], rotation=40, ha="right")
    ax.set_ylabel("Revenue (R$ million)")
    ax2 = ax.twinx(); ax2.spines["right"].set_visible(True)
    ax2.plot(range(len(top)), top["cum"], color=ORANGE, marker="o", lw=2)
    ax2.set_ylim(0, 100); ax2.set_ylabel("Cumulative share of revenue (%)")
    n80 = int((df["cum"] < 80).sum() + 1)
    ax.set_title(f"{n80} of {len(df)} categories generate 80% of revenue")
    _save("fig02_category_pareto.png")


# ------------------------------------------------------------------ 3. delivery
def fig_delivery_by_state(engine):
    df = pd.read_sql(
        """SELECT customer_state AS state, COUNT(*) AS n,
                  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days) AS median_days,
                  100.0 * AVG(is_late::INT) AS late_pct
           FROM olist.vw_order_facts WHERE is_delivered AND in_analysis_window
           GROUP BY 1 HAVING COUNT(*) >= 300 ORDER BY median_days""", engine)
    fig, axes = plt.subplots(1, 2, figsize=(9, 6), sharey=True)
    y = np.arange(len(df))
    axes[0].barh(y, df["median_days"], color=NAVY); axes[0].set_xlabel("Median delivery time (days)")
    axes[1].barh(y, df["late_pct"], color=ORANGE); axes[1].set_xlabel("Orders delivered late (%)")
    axes[0].set_yticks(y); axes[0].set_yticklabels(df["state"])
    fig.suptitle("Delivery is slowest and least reliable in the north and north-east", fontweight="bold")
    plt.tight_layout()
    _save("fig03_delivery_by_state.png")


def fig_late_rate_monthly(engine):
    df = pd.read_sql(
        """SELECT purchase_month AS month, 100.0 * AVG(is_late::INT) AS late_pct
           FROM olist.vw_order_facts WHERE is_delivered AND in_analysis_window
           GROUP BY 1 ORDER BY 1""", engine)
    df["month"] = pd.to_datetime(df["month"])
    fig, ax = plt.subplots(figsize=(9, 3.6))
    ax.plot(df["month"], df["late_pct"], color=RED, lw=2.2, marker="o", ms=4)
    for label, m, dx in [("Nov 2017", "2017-11-01", -92), ("Mar 2018", "2018-03-01", 10)]:
        r = df[df["month"] == m].iloc[0]
        ax.annotate(f"{label}: {r.late_pct:.1f}%", (r["month"], r.late_pct),
                    xytext=(dx, -3), textcoords="offset points", fontsize=9)
    ax.set_ylabel("Late deliveries (%)"); ax.set_ylim(0, df["late_pct"].max() * 1.2)
    ax.set_title("Late deliveries spike during demand peaks")
    _save("fig04_late_rate_monthly.png")


# ---------------------------------------------------------------- 4. delay vs review
def fig_delay_vs_review(engine):
    df = pd.read_sql(
        """SELECT CASE WHEN delay_days <= -7 THEN '1. 7+ days early'
                       WHEN delay_days <= 0  THEN '2. 0-7 days early'
                       WHEN delay_days <= 3  THEN '3. 1-3 days late'
                       WHEN delay_days <= 7  THEN '4. 3-7 days late'
                       ELSE '5. 7+ days late' END AS bucket,
                  AVG(review_score)::float AS score, COUNT(*) AS n
           FROM olist.vw_order_facts
           WHERE is_delivered AND in_analysis_window AND review_score IS NOT NULL
           GROUP BY 1 ORDER BY 1""", engine)
    df["label"] = df["bucket"].str[3:]
    fig, ax = plt.subplots(figsize=(9, 4))
    colors = [NAVY, NAVY, ORANGE, RED, RED]
    ax.bar(df["label"], df["score"], color=colors)
    for i, (s, n) in enumerate(zip(df["score"], df["n"])):
        ax.text(i, s + 0.05, f"{s:.2f}\n(n={n:,})", ha="center", fontsize=9)
    ax.set_ylim(0, 5.2); ax.set_ylabel("Average review score (1-5)")
    ax.set_title("Review scores fall off a cliff once an order is more than 3 days late")
    _save("fig05_delay_vs_review.png")


# --------------------------------------------------------------- 5. customer value
def fig_customer_concentration(engine):
    df = pd.read_sql("SELECT revenue::float AS revenue FROM olist.vw_customer_summary", engine)
    df = df.sort_values("revenue", ascending=False).reset_index(drop=True)
    df["decile"] = pd.qcut(df.index, 10, labels=range(1, 11))
    share = 100 * df.groupby("decile", observed=True)["revenue"].sum() / df["revenue"].sum()
    fig, ax = plt.subplots(figsize=(9, 3.8))
    ax.bar(share.index.astype(str), share.values, color=[NAVY] + [LIGHT] * 9)
    for i, v in enumerate(share.values):
        ax.text(i, v + 0.6, f"{v:.0f}%", ha="center", fontsize=9)
    ax.set_xlabel("Customer decile (1 = highest spenders)"); ax.set_ylabel("Share of revenue (%)")
    ax.set_title("The top 10% of customers generate 41% of revenue")
    _save("fig06_customer_concentration.png")


# ------------------------------------------------- 6. segmentation and retention
def fig_rfm_segments(engine):
    summary = sg.segment_summary(sg.build_segments(engine)).iloc[::-1]
    fig, ax = plt.subplots(figsize=(9, 4.5))
    y = np.arange(len(summary)); h = 0.38
    ax.barh(y + h / 2, summary.pct_customers, h, label="% of customers", color=LIGHT)
    ax.barh(y - h / 2, summary.pct_revenue, h, label="% of revenue", color=NAVY)
    ax.set_yticks(y); ax.set_yticklabels(summary.index)
    for i, (c, r) in enumerate(zip(summary.pct_customers, summary.pct_revenue)):
        ax.text(c + .4, i + h / 2, f"{c:.1f}%", va="center", fontsize=8)
        ax.text(r + .4, i - h / 2, f"{r:.1f}%", va="center", fontsize=8)
    ax.set_xlabel("share (%)"); ax.set_title("RFM segments: share of customers vs share of revenue")
    ax.legend(frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.14), ncol=2)
    _save("rfm_segments.png")


def fig_cohort_heatmap(engine):
    coh = pd.read_sql("SELECT cohort_month, month_index, retention_pct::float AS r "
                      "FROM olist.vw_cohort_retention", engine)
    coh["cohort_month"] = pd.to_datetime(coh["cohort_month"])
    m = coh[(coh.cohort_month <= "2018-02-01") & coh.month_index.between(1, 6)].copy()
    m["cohort"] = m.cohort_month.dt.strftime("%Y-%m")
    piv = m.pivot(index="cohort", columns="month_index", values="r")
    fig, ax = plt.subplots(figsize=(7, 6))
    sns.heatmap(piv, annot=True, fmt=".2f", cmap="Blues", cbar_kws={"label": "% of cohort ordering again"}, ax=ax)
    ax.set_title("Monthly retention by cohort (months since first order)")
    ax.set_xlabel("months since first order"); ax.set_ylabel("")
    _save("cohort_heatmap.png")


def fig_repeat_by_category(engine):
    fo = sg.load_first_orders(engine)
    c = fo.groupby("first_category")["repeat"].agg(["sum", "count"]).query("count >= 1000")
    c["rate"] = 100 * c["sum"] / c["count"]
    c["lo"], c["hi"] = [100 * v for v in sg.wilson_ci(c["sum"], c["count"])]
    c = c.sort_values("rate")
    fig, ax = plt.subplots(figsize=(8, 6))
    ax.errorbar(c.rate, range(len(c)), xerr=[c.rate - c.lo, c.hi - c.rate], fmt="o", color=NAVY, capsize=3)
    ax.axvline(100 * fo["repeat"].mean(), color=GREY, ls="--", label="overall rate")
    ax.set_yticks(range(len(c))); ax.set_yticklabels(c.index)
    ax.set_xlabel("% who reorder within 180 days (95% CI)")
    ax.set_title("Repeat rate by category of first purchase"); ax.legend(frameon=False)
    _save("repeat_by_category.png")


ALL = [fig_revenue_trend, fig_category_pareto, fig_delivery_by_state, fig_late_rate_monthly,
       fig_delay_vs_review, fig_customer_concentration, fig_rfm_segments,
       fig_cohort_heatmap, fig_repeat_by_category]


def main(engine=None):
    engine = engine or sg.get_engine()
    print("Generating figures ...")
    for f in ALL:
        f(engine)


if __name__ == "__main__":
    main()
