"""
Phase 4 - Customer segmentation and retention helpers.

Used by notebooks/04_segmentation.ipynb. Reads from the PostgreSQL views built
in Phase 2/3 (vw_customer_summary, vw_cohort_retention, vw_first_order_profile).
Connection string: environment variable DATABASE_URL (same one src/db_load.py uses).
"""
from __future__ import annotations

import os

import numpy as np
import pandas as pd
from sqlalchemy import create_engine

from src import config

SNAPSHOT_DATE = pd.Timestamp("2018-09-01")   # first day after the last complete month

SEGMENT_ORDER = [
    "New big spenders",
    "At-risk big spenders",
    "Mid-age big spenders",
    "Loyal repeaters",
    "Lapsed repeaters",
    "Recent small buyers",
    "Lost / low value",
]


def get_engine(url: str | None = None):
    url = url or config.database_url()
    # SQLAlchemy needs the driver in the scheme: postgresql+psycopg2://
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+psycopg2://", 1)
    return create_engine(url)


# ----------------------------------------------------------------------------
# RFM
# ----------------------------------------------------------------------------
def load_customers(engine) -> pd.DataFrame:
    df = pd.read_sql(
        "SELECT customer_unique_id, orders, revenue::float AS revenue, "
        "first_order_at, last_order_at, state, avg_review::float AS avg_review "
        "FROM olist.vw_customer_summary",
        engine,
    )
    df = df[df["last_order_at"] < SNAPSHOT_DATE].copy()
    df["recency_days"] = (SNAPSHOT_DATE - df["last_order_at"]).dt.total_seconds() / 86_400
    return df


def score_rfm(df: pd.DataFrame) -> pd.DataFrame:
    """R and M are quintiles (5 = best). Frequency is NOT scored in quintiles:
    97% of customers have exactly 1 order, so quintiles would be meaningless.
    Repeat buying is handled as an explicit rule in assign_segment()."""
    out = df.copy()
    out["R"] = pd.qcut(out["recency_days"].rank(method="first"), 5, labels=[5, 4, 3, 2, 1]).astype(int)
    out["M"] = pd.qcut(out["revenue"].rank(method="first"), 5, labels=[1, 2, 3, 4, 5]).astype(int)
    out["F"] = np.where(out["orders"] >= 2, 2, 1)
    return out


def assign_segment(row) -> str:
    if row["F"] == 2:
        return "Loyal repeaters" if row["R"] >= 3 else "Lapsed repeaters"
    if row["M"] >= 4:
        if row["R"] >= 4:
            return "New big spenders"
        return "At-risk big spenders" if row["R"] <= 2 else "Mid-age big spenders"
    return "Recent small buyers" if row["R"] >= 4 else "Lost / low value"


def build_segments(engine) -> pd.DataFrame:
    df = score_rfm(load_customers(engine))
    df["segment"] = df.apply(assign_segment, axis=1)
    df["segment"] = pd.Categorical(df["segment"], SEGMENT_ORDER, ordered=True)
    return df


def segment_summary(df: pd.DataFrame) -> pd.DataFrame:
    t = df.groupby("segment", observed=True).agg(
        customers=("revenue", "size"),
        revenue=("revenue", "sum"),
        avg_revenue=("revenue", "mean"),
        median_recency_days=("recency_days", "median"),
        avg_review=("avg_review", "mean"),
    )
    t["pct_customers"] = 100 * t["customers"] / t["customers"].sum()
    t["pct_revenue"] = 100 * t["revenue"] / t["revenue"].sum()
    return t.round(1)


# ----------------------------------------------------------------------------
# Statistics for the retention analysis
# ----------------------------------------------------------------------------
def wilson_ci(k, n, z: float = 1.96):
    """95% Wilson score interval for a proportion (robust for small rates)."""
    k, n = np.asarray(k, float), np.asarray(n, float)
    p = k / n
    denom = 1 + z**2 / n
    centre = (p + z**2 / (2 * n)) / denom
    half = z * np.sqrt(p * (1 - p) / n + z**2 / (4 * n**2)) / denom
    return centre - half, centre + half


def load_first_orders(engine, cutoff: str = "2018-02-28") -> pd.DataFrame:
    """Customers whose first order leaves a full 180-day follow-up window.
    `repeat` = a 2nd order placed more than 24h and at most 180 days later."""
    df = pd.read_sql(
        "SELECT customer_unique_id, first_order_at, first_category, first_order_value::float AS first_order_value, "
        "first_payment_type, first_installments, state, first_review_score, first_is_late, "
        "first_is_delivered, days_to_second::float AS days_to_second "
        "FROM olist.vw_first_order_profile WHERE first_order_at <= %(cutoff)s",
        engine,
        params={"cutoff": cutoff},
    )
    df["repeat"] = (df["days_to_second"] > 1) & (df["days_to_second"] <= 180)
    return df


# ----------------------------------------------------------------------------
# Publish segments back to the database (feeds the Power BI dim_customer view)
# ----------------------------------------------------------------------------
def publish_segments(engine) -> int:
    """Write one row per customer to olist.customer_segments (table is created by
    sql/05_powerbi_model.sql). TRUNCATE + append, so dependent views keep working."""
    from sqlalchemy import text

    seg = build_segments(engine)
    out = pd.DataFrame(
        {
            "customer_unique_id": seg["customer_unique_id"],
            "orders": seg["orders"].astype(int),
            "lifetime_revenue": seg["revenue"].round(2),
            "recency_days": seg["recency_days"].round(1),
            "r_score": seg["R"].astype(int),
            "m_score": seg["M"].astype(int),
            "segment": seg["segment"].astype(str),
        }
    )
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE TABLE olist.customer_segments"))
    out.to_sql("customer_segments", engine, schema="olist", if_exists="append",
               index=False, method="multi", chunksize=5000)
    return len(out)
