"""
Unit tests for the pure-Python logic (no database needed):  pytest -q
Database reconciliation lives in sql/04_validation.sql and src/run_pipeline.py.
"""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import cleaning, config
from src import segmentation as sg


# ------------------------------------------------------------------ cleaning
def _orders():
    return pd.DataFrame({
        "order_id": ["a", "b", "c", "d"],
        "customer_id": ["c1", "c2", "c3", "c4"],
        "order_status": ["delivered", "delivered", "canceled", "shipped"],
        "order_purchase_timestamp": ["2017-03-01 10:00:00"] * 4,
        "order_approved_at": ["2017-03-01 11:00:00"] * 4,
        "order_delivered_carrier_date": ["2017-03-02 10:00:00"] * 4,
        "order_delivered_customer_date": ["2017-03-11 10:00:00", "2017-03-30 10:00:00", None, None],
        "order_estimated_delivery_date": ["2017-03-20 00:00:00"] * 4,
    })


def test_orders_flags_and_delivery_metrics():
    items = pd.DataFrame({"order_id": ["a", "b"]})
    o = cleaning.clean_orders(_orders(), items, {}).set_index("order_id")
    assert o.loc["a", "delivery_days"] == pytest.approx(10.0)
    assert not o.loc["a", "is_late"]              # delivered before the estimate
    assert o.loc["b", "is_late"]                  # delivered 10 days after the estimate
    assert o.loc["b", "delay_days"] == pytest.approx(10.4166, abs=1e-3)
    assert o.loc["c", "is_valid_sale"] == False   # canceled is not a sale
    assert pd.isna(o.loc["d", "delivery_days"])   # not delivered: no delivery metrics
    assert o.loc["a", "in_analysis_window"]
    assert not o.loc["c", "has_items"]


def test_zip_codes_keep_leading_zeros():
    assert _zip_ok(pd.Series(["1046", "13"]))


def _zip_ok(s):
    return list(cleaning._zip(s)) == ["01046", "00013"]


def test_city_normalisation_removes_accents_and_case():
    out = cleaning._norm_text(pd.Series(["São Paulo ", "sao paulo", None]))
    assert out.iloc[0] == out.iloc[1] == "sao paulo"
    assert pd.isna(out.iloc[2])


def test_reviews_keep_latest_per_order():
    rev = pd.DataFrame({
        "review_id": ["r1", "r2", "r3"], "order_id": ["o1", "o1", "o2"],
        "review_score": [1, 5, 3], "review_comment_title": [None] * 3, "review_comment_message": [None, "ok", None],
        "review_creation_date": ["2017-01-01"] * 3,
        "review_answer_timestamp": ["2017-01-02 10:00:00", "2017-01-05 10:00:00", "2017-01-03 10:00:00"],
    })
    out = cleaning.clean_order_reviews(rev, {}).set_index("order_id")
    assert len(out) == 2
    assert out.loc["o1", "review_score"] == 5     # the later answer wins


# -------------------------------------------------------------- segmentation
def test_assign_segment_rules():
    f = sg.assign_segment
    assert f({"F": 2, "R": 5, "M": 1}) == "Loyal repeaters"
    assert f({"F": 2, "R": 2, "M": 5}) == "Lapsed repeaters"
    assert f({"F": 1, "R": 5, "M": 5}) == "New big spenders"
    assert f({"F": 1, "R": 1, "M": 4}) == "At-risk big spenders"
    assert f({"F": 1, "R": 3, "M": 5}) == "Mid-age big spenders"
    assert f({"F": 1, "R": 4, "M": 2}) == "Recent small buyers"
    assert f({"F": 1, "R": 1, "M": 1}) == "Lost / low value"


def test_every_segment_is_listed():
    seen = {sg.assign_segment({"F": F, "R": R, "M": M}) for F in (1, 2) for R in range(1, 6) for M in range(1, 6)}
    assert seen == set(sg.SEGMENT_ORDER)


def test_score_rfm_quintiles_are_balanced():
    rng = np.random.RandomState(1)
    df = pd.DataFrame({"recency_days": rng.uniform(1, 600, 1000), "revenue": rng.uniform(10, 500, 1000),
                       "orders": rng.choice([1, 1, 1, 2], 1000)})
    out = sg.score_rfm(df)
    assert out["R"].value_counts().min() == 200 and out["M"].value_counts().min() == 200
    assert set(out["F"]) == {1, 2}
    # most recent customers get R = 5
    assert out.loc[out["recency_days"].idxmin(), "R"] == 5


def test_wilson_ci_properties():
    lo, hi = sg.wilson_ci(50, 1000)
    assert 0 < lo < 0.05 < hi < 1
    lo0, hi0 = sg.wilson_ci(0, 100)
    assert lo0 == pytest.approx(0, abs=1e-9) and hi0 > 0    # never collapses to a zero-width interval
    small_lo, small_hi = sg.wilson_ci(5, 100)
    big_lo, big_hi = sg.wilson_ci(500, 10000)
    assert (small_hi - small_lo) > (big_hi - big_lo)          # more data, narrower interval


# -------------------------------------------------------------------- config
def test_env_file_parsing(tmp_path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text("# comment\nDATABASE_URL='postgresql://u:p@h:1234/db'\n\nEMPTY\n")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    config.load_env(env)
    assert config.os.environ["DATABASE_URL"] == "postgresql://u:p@h:1234/db"
    monkeypatch.setenv("DATABASE_URL", "postgresql://real")      # real env vars win over the file
    config.load_env(env)
    assert config.os.environ["DATABASE_URL"] == "postgresql://real"
