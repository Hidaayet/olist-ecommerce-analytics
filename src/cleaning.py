"""
Phase 1 - Cleaning pipeline for the Olist Brazilian E-Commerce dataset.

Run from the repo root:
    python -m src.cleaning                       # data/raw -> data/clean
    python -m src.cleaning --raw X --clean Y     # custom paths

Design principles (see docs/decisions_log.md):
  * Reversible: nothing that is "suspicious" is dropped, it is FLAGGED.
    The only rows removed are exact/logical duplicates (reviews, geolocation).
  * Every transformation is counted and written to cleaning_log.json.
  * Tables stay at their natural grain. Aggregation (order-level revenue,
    payments per order, ...) happens in SQL, which avoids join fan-out.
"""
from __future__ import annotations

import argparse
import json
import unicodedata
from pathlib import Path

import numpy as np
import pandas as pd

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
RAW_FILES = {
    "orders": "olist_orders_dataset",
    "order_items": "olist_order_items_dataset",
    "order_payments": "olist_order_payments_dataset",
    "order_reviews": "olist_order_reviews_dataset",
    "customers": "olist_customers_dataset",
    "sellers": "olist_sellers_dataset",
    "products": "olist_products_dataset",
    "geolocation": "olist_geolocation_dataset",
    "category_translation": "product_category_name_translation",
}

# Zip prefixes are read as text: the raw CSVs store them as integers, which
# silently drops leading zeros (01046 -> 1046) and breaks joins to geolocation.
ZIP_COLS = {
    "customers": "customer_zip_code_prefix",
    "sellers": "seller_zip_code_prefix",
    "geolocation": "geolocation_zip_code_prefix",
}

ORDER_TS = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date",
]

NON_SALE_STATUSES = ["canceled", "unavailable"]

# Months with a complete, meaningful order flow (see decisions log, D-06).
WINDOW_START = pd.Timestamp("2017-01-01")
WINDOW_END = pd.Timestamp("2018-09-01")  # exclusive

# Categories present in products but missing from the translation table.
MANUAL_TRANSLATIONS = {
    "pc_gamer": "pc_gamer",
    "portateis_cozinha_e_preparadores_de_alimentos": "portable_kitchen_food_preparers",
    "unknown": "unknown",
}

# Rough bounding box of Brazil, used to discard impossible coordinates.
BRAZIL_LAT = (-34.0, 6.0)
BRAZIL_LNG = (-74.0, -34.0)

SECONDS_PER_DAY = 86_400


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
def _norm_text(s: pd.Series) -> pd.Series:
    """lowercase, strip, remove accents (so 'São Paulo' == 'sao paulo')."""
    def fix(x):
        if pd.isna(x):
            return x
        x = unicodedata.normalize("NFKD", str(x)).encode("ascii", "ignore").decode()
        return x.strip().lower()
    return s.map(fix)


def _zip(s: pd.Series) -> pd.Series:
    return s.astype("string").str.strip().str.zfill(5)


# ----------------------------------------------------------------------------
# Load
# ----------------------------------------------------------------------------
def load_raw(raw_dir: Path) -> dict[str, pd.DataFrame]:
    raw = {}
    for name, stem in RAW_FILES.items():
        dtype = {ZIP_COLS[name]: "string"} if name in ZIP_COLS else None
        raw[name] = pd.read_csv(Path(raw_dir) / f"{stem}.csv", dtype=dtype)
    return raw


# ----------------------------------------------------------------------------
# Table cleaners
# ----------------------------------------------------------------------------
def clean_orders(orders: pd.DataFrame, items: pd.DataFrame, log: dict) -> pd.DataFrame:
    o = orders.copy()
    o["order_status"] = o["order_status"].str.strip().str.lower()
    for c in ORDER_TS:
        o[c] = pd.to_datetime(o[c], errors="coerce")

    # --- flags -------------------------------------------------------------
    o["has_items"] = o["order_id"].isin(items["order_id"])
    o["is_valid_sale"] = ~o["order_status"].isin(NON_SALE_STATUSES)
    o["is_delivered"] = (o["order_status"] == "delivered") & o[
        "order_delivered_customer_date"
    ].notna()
    purchase = o["order_purchase_timestamp"]
    o["in_analysis_window"] = (purchase >= WINDOW_START) & (purchase < WINDOW_END)

    # timestamp sequence anomalies (informational; rows are kept)
    o["ts_anomaly"] = (
        (o["order_approved_at"] < purchase)
        | (o["order_delivered_carrier_date"] < purchase)
        | (o["order_delivered_customer_date"] < o["order_delivered_carrier_date"])
    )

    # --- delivery metrics: only for genuinely delivered orders ---------------
    deliv = o["order_delivered_customer_date"].where(o["is_delivered"])
    est = o["order_estimated_delivery_date"]
    o["delivery_days"] = (deliv - purchase).dt.total_seconds() / SECONDS_PER_DAY
    o["estimated_days"] = (est - purchase).dt.total_seconds() / SECONDS_PER_DAY
    o["delay_days"] = (deliv - est).dt.total_seconds() / SECONDS_PER_DAY  # >0 = late
    o["is_late"] = pd.array(
        np.where(deliv.notna(), o["delay_days"] > 0, pd.NA), dtype="boolean"
    )
    o["purchase_month"] = purchase.dt.strftime("%Y-%m-01")

    log["orders"] = {
        "rows": len(o),
        "status_counts": o["order_status"].value_counts().to_dict(),
        "orders_without_items": int((~o["has_items"]).sum()),
        "not_valid_sale": int((~o["is_valid_sale"]).sum()),
        "delivered_status_missing_date": int(
            ((o["order_status"] == "delivered") & ~o["is_delivered"]).sum()
        ),
        "delivered_with_metrics": int(o["is_delivered"].sum()),
        "late_deliveries": int(o["is_late"].fillna(False).sum()),
        "ts_anomalies": int(o["ts_anomaly"].sum()),
        "outside_analysis_window": int((~o["in_analysis_window"]).sum()),
        "purchase_min": str(purchase.min()),
        "purchase_max": str(purchase.max()),
    }
    return o


def clean_order_items(items: pd.DataFrame, log: dict) -> pd.DataFrame:
    i = items.copy()
    i["shipping_limit_date"] = pd.to_datetime(i["shipping_limit_date"], errors="coerce")
    i["item_total"] = (i["price"] + i["freight_value"]).round(2)
    log["order_items"] = {"rows": len(i), "orders": int(i["order_id"].nunique())}
    return i


def clean_order_payments(pay: pd.DataFrame, log: dict) -> pd.DataFrame:
    p = pay.copy()
    p["payment_type"] = p["payment_type"].str.strip().str.lower()
    p["is_zero_value"] = p["payment_value"] <= 0
    log["order_payments"] = {
        "rows": len(p),
        "zero_or_negative_value": int(p["is_zero_value"].sum()),
        "not_defined_type": int((p["payment_type"] == "not_defined").sum()),
        "orders_with_multiple_rows": int((p["order_id"].value_counts() > 1).sum()),
    }
    return p


def clean_order_reviews(rev: pd.DataFrame, log: dict) -> pd.DataFrame:
    r = rev.copy()
    for c in ["review_creation_date", "review_answer_timestamp"]:
        r[c] = pd.to_datetime(r[c], errors="coerce")
    before = len(r)
    multi = int((r["order_id"].value_counts() > 1).sum())
    dup_review_ids = int(r["review_id"].duplicated().sum())

    # keep the most recent review per order
    r = (
        r.sort_values(["order_id", "review_answer_timestamp", "review_creation_date"])
        .drop_duplicates("order_id", keep="last")
        .reset_index(drop=True)
    )
    r["has_comment"] = r["review_comment_message"].notna()
    log["order_reviews"] = {
        "rows_before": before,
        "rows_after": len(r),
        "rows_dropped": before - len(r),
        "orders_with_multiple_reviews": multi,
        "duplicate_review_ids_in_raw": dup_review_ids,
        "review_id_unique_after": bool(r["review_id"].is_unique),
        "note": "grain is one review per order; PK = order_id",
    }
    return r


def clean_customers(cust: pd.DataFrame, log: dict) -> pd.DataFrame:
    c = cust.copy()
    c["customer_zip_code_prefix"] = _zip(c["customer_zip_code_prefix"])
    c["customer_city"] = _norm_text(c["customer_city"])
    c["customer_state"] = c["customer_state"].str.strip().str.upper()
    log["customers"] = {
        "rows": len(c),
        "unique_people": int(c["customer_unique_id"].nunique()),
    }
    return c


def clean_sellers(sell: pd.DataFrame, log: dict) -> pd.DataFrame:
    s = sell.copy()
    s["seller_zip_code_prefix"] = _zip(s["seller_zip_code_prefix"])
    s["seller_city"] = _norm_text(s["seller_city"])
    s["seller_state"] = s["seller_state"].str.strip().str.upper()
    log["sellers"] = {"rows": len(s)}
    return s


def clean_products(prod: pd.DataFrame, trans: pd.DataFrame, log: dict):
    p = prod.rename(
        columns={
            "product_name_lenght": "product_name_length",
            "product_description_lenght": "product_description_length",
        }
    )
    missing_cat = int(p["product_category_name"].isna().sum())
    p["product_category_name"] = p["product_category_name"].fillna("unknown")

    t = pd.concat(
        [
            trans,
            pd.DataFrame(
                {
                    "product_category_name": list(MANUAL_TRANSLATIONS),
                    "product_category_name_english": list(MANUAL_TRANSLATIONS.values()),
                }
            ),
        ],
        ignore_index=True,
    ).drop_duplicates("product_category_name")

    p = p.merge(t, on="product_category_name", how="left", validate="m:1")
    p["has_missing_dimensions"] = p[
        ["product_weight_g", "product_length_cm", "product_height_cm", "product_width_cm"]
    ].isna().any(axis=1)
    for c in ["product_name_length", "product_description_length", "product_photos_qty"]:
        p[c] = p[c].astype("Int64")

    log["products"] = {
        "rows": len(p),
        "missing_category_filled_unknown": missing_cat,
        "untranslated_categories_mapped_manually": [
            k for k in MANUAL_TRANSLATIONS if k != "unknown"
        ],
        "still_untranslated_rows": int(p["product_category_name_english"].isna().sum()),
        "missing_dimensions": int(p["has_missing_dimensions"].sum()),
    }
    return p, t.reset_index(drop=True)


def clean_geolocation(geo: pd.DataFrame, log: dict) -> pd.DataFrame:
    g = geo.copy()
    n_raw = len(g)
    g["geolocation_zip_code_prefix"] = _zip(g["geolocation_zip_code_prefix"])
    g["geolocation_city"] = _norm_text(g["geolocation_city"])
    g["geolocation_state"] = g["geolocation_state"].str.strip().str.upper()

    exact_dups = int(g.duplicated().sum())
    in_brazil = g["geolocation_lat"].between(*BRAZIL_LAT) & g["geolocation_lng"].between(
        *BRAZIL_LNG
    )
    outside = int((~in_brazil).sum())
    g = g[in_brazil]

    key = "geolocation_zip_code_prefix"
    coords = g.groupby(key, as_index=False).agg(
        geolocation_lat=("geolocation_lat", "median"),
        geolocation_lng=("geolocation_lng", "median"),
        n_raw_points=("geolocation_lat", "size"),
    )
    # most frequent city/state label for each zip prefix
    label = (
        g.groupby([key, "geolocation_city", "geolocation_state"]).size().rename("n").reset_index()
        .sort_values([key, "n"], ascending=[True, False])
        .drop_duplicates(key)[[key, "geolocation_city", "geolocation_state"]]
    )
    out = coords.merge(label, on=key, validate="1:1")

    log["geolocation"] = {
        "rows_raw": n_raw,
        "exact_duplicate_rows": exact_dups,
        "points_outside_brazil_dropped": outside,
        "rows_clean": len(out),
        "note": "collapsed to one row per zip prefix (median lat/lng, modal city/state)",
    }
    return out


# ----------------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------------
def validate(c: dict[str, pd.DataFrame], log: dict) -> list[dict]:
    checks: list[dict] = []

    def add(name, ok, detail="", hard=True):
        checks.append({"check": name, "passed": bool(ok), "hard": hard, "detail": detail})

    # primary keys
    add("PK orders.order_id unique", c["orders"]["order_id"].is_unique)
    add("PK customers.customer_id unique", c["customers"]["customer_id"].is_unique)
    add("PK products.product_id unique", c["products"]["product_id"].is_unique)
    add("PK sellers.seller_id unique", c["sellers"]["seller_id"].is_unique)
    add("PK order_reviews.order_id unique", c["order_reviews"]["order_id"].is_unique)
    add(
        "PK order_items (order_id, order_item_id) unique",
        not c["order_items"].duplicated(["order_id", "order_item_id"]).any(),
    )
    add(
        "PK order_payments (order_id, payment_sequential) unique",
        not c["order_payments"].duplicated(["order_id", "payment_sequential"]).any(),
    )
    add("PK geolocation.zip_prefix unique", c["geolocation"]["geolocation_zip_code_prefix"].is_unique)

    # foreign keys
    def fk(child, col, parent, pcol, hard=True):
        miss = int((~c[child][col].isin(c[parent][pcol])).sum())
        add(f"FK {child}.{col} -> {parent}.{pcol}", miss == 0, f"{miss} orphan rows", hard)

    fk("orders", "customer_id", "customers", "customer_id")
    fk("order_items", "order_id", "orders", "order_id")
    fk("order_items", "product_id", "products", "product_id")
    fk("order_items", "seller_id", "sellers", "seller_id")
    fk("order_payments", "order_id", "orders", "order_id")
    fk("order_reviews", "order_id", "orders", "order_id")
    # geolocation coverage is informational only: not every zip has coordinates
    fk("customers", "customer_zip_code_prefix", "geolocation", "geolocation_zip_code_prefix", hard=False)
    fk("sellers", "seller_zip_code_prefix", "geolocation", "geolocation_zip_code_prefix", hard=False)

    # domain checks
    o, i = c["orders"], c["order_items"]
    add("review_score within 1..5", c["order_reviews"]["review_score"].between(1, 5).all())
    add("item price > 0", (i["price"] > 0).all())
    add("item freight >= 0", (i["freight_value"] >= 0).all())
    add("no delivered order has negative delivery_days", not (o["delivery_days"] < 0).any())
    add("no null category_english in products", c["products"]["product_category_name_english"].notna().all())
    add("all order timestamps parsed (purchase)", o["order_purchase_timestamp"].notna().all())

    # reconciliation: item value (price+freight) vs payments, informational
    items_tot = i.groupby("order_id")["item_total"].sum()
    pay_tot = c["order_payments"].groupby("order_id")["payment_value"].sum()
    both = pd.concat([items_tot, pay_tot], axis=1, join="inner")
    # round to cents first: float subtraction can land a hair above 0.01 at the boundary
    match = ((both["item_total"] - both["payment_value"]).round(2).abs() <= 0.01).mean()
    add(
        "orders where items(price+freight) == payments (+-0.01)",
        True,
        f"{match:.1%} of {len(both):,} orders match; the rest are explained in decisions log D-18",
        hard=False,
    )

    # fan-out demonstration for the decisions log
    naive = i.merge(c["order_payments"], on="order_id")
    log["fanout_demo"] = {
        "item_price_sum": round(float(i["price"].sum()), 2),
        "naive_items_x_payments_price_sum": round(float(naive["price"].sum()), 2),
        "inflation_pct": round(float(naive["price"].sum() / i["price"].sum() - 1) * 100, 2),
    }
    return checks


# ----------------------------------------------------------------------------
# Orchestration
# ----------------------------------------------------------------------------
def run(raw_dir="data/raw", clean_dir="data/clean", strict=True, verbose=True):
    raw_dir, clean_dir = Path(raw_dir), Path(clean_dir)
    raw = load_raw(raw_dir)
    log: dict = {}

    products, translation = clean_products(raw["products"], raw["category_translation"], log)
    clean = {
        "orders": clean_orders(raw["orders"], raw["order_items"], log),
        "order_items": clean_order_items(raw["order_items"], log),
        "order_payments": clean_order_payments(raw["order_payments"], log),
        "order_reviews": clean_order_reviews(raw["order_reviews"], log),
        "customers": clean_customers(raw["customers"], log),
        "sellers": clean_sellers(raw["sellers"], log),
        "products": products,
        "category_translation": translation,
        "geolocation": clean_geolocation(raw["geolocation"], log),
    }

    results = validate(clean, log)
    log["validation"] = results

    clean_dir.mkdir(parents=True, exist_ok=True)
    for name, df in clean.items():
        df.to_csv(clean_dir / f"{name}.csv", index=False)
    (clean_dir / "cleaning_log.json").write_text(json.dumps(log, indent=2, default=str))

    if verbose:
        print(f"{'table':<22}{'rows':>10}  cols")
        for name, df in clean.items():
            print(f"{name:<22}{len(df):>10,}  {df.shape[1]}")
        print("\nValidation")
        for r in results:
            mark = "PASS" if r["passed"] else ("FAIL" if r["hard"] else "WARN")
            print(f"  [{mark}] {r['check']}  {r['detail']}")
        print(f"\nClean files written to {clean_dir.resolve()}")

    failed = [r for r in results if r["hard"] and not r["passed"]]
    if strict and failed:
        raise AssertionError(f"{len(failed)} hard validation check(s) failed: "
                             + "; ".join(r["check"] for r in failed))
    return clean, log, results


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Clean the Olist dataset")
    ap.add_argument("--raw", default="data/raw")
    ap.add_argument("--clean", default="data/clean")
    ap.add_argument("--no-strict", action="store_true", help="don't raise on failed checks")
    a = ap.parse_args()
    run(a.raw, a.clean, strict=not a.no_strict)
