"""
Phase 2 - Build the PostgreSQL database from the clean CSVs.

    python -m src.db_load      # uses DATABASE_URL from the environment or from the .env file (see src/config.py)

Steps: create schema -> COPY tables in FK order -> ANALYZE -> create views
       -> verify row counts against the CSVs.
Equivalent to running sql/01_schema.sql, sql/02_load.sql and
sql/03_analysis/00_base_views.sql in psql, but cross-platform.
"""
from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path

import psycopg2

from src import config

DEFAULT_URL = config.DEFAULT_URL

# parents first, children after (foreign-key order)
LOAD_ORDER = [
    "category_translation",
    "geolocation",
    "customers",
    "sellers",
    "products",
    "orders",
    "order_items",
    "order_payments",
    "order_reviews",
]


def _csv_header(path: Path) -> list[str]:
    with open(path, newline="", encoding="utf-8") as f:
        return next(csv.reader(f))


def _csv_rows(path: Path) -> int:
    with open(path, newline="", encoding="utf-8") as f:
        return sum(1 for _ in csv.reader(f)) - 1


def run(database_url: str | None = None, clean_dir="data/clean", sql_dir="sql") -> dict:
    database_url = database_url or config.database_url()
    clean_dir, sql_dir = Path(clean_dir), Path(sql_dir)
    missing = [t for t in LOAD_ORDER if not (clean_dir / f"{t}.csv").exists()]
    if missing:
        raise FileNotFoundError(f"Run `python -m src.cleaning` first. Missing: {missing}")

    counts = {}
    with psycopg2.connect(database_url) as conn:
        with conn.cursor() as cur:
            print("Creating schema ...")
            cur.execute((sql_dir / "01_schema.sql").read_text(encoding="utf-8"))
            cur.execute("SET search_path TO olist")

            for table in LOAD_ORDER:
                path = clean_dir / f"{table}.csv"
                cols = ", ".join(_csv_header(path))
                with open(path, encoding="utf-8") as f:
                    cur.copy_expert(
                        f"COPY olist.{table} ({cols}) FROM STDIN WITH (FORMAT csv, HEADER true)", f
                    )
                cur.execute(f"SELECT COUNT(*) FROM olist.{table}")
                counts[table] = cur.fetchone()[0]
                expected = _csv_rows(path)
                status = "OK" if counts[table] == expected else f"MISMATCH (csv has {expected:,})"
                print(f"  loaded {table:<22}{counts[table]:>10,}  {status}")
                if counts[table] != expected:
                    raise RuntimeError(f"Row count mismatch for {table}")

            print("Analyzing + creating views ...")
            cur.execute("ANALYZE")
            cur.execute((sql_dir / "03_analysis" / "00_base_views.sql").read_text(encoding="utf-8"))
    print("Database ready. Next: psql -f sql/04_validation.sql")
    return counts


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=None, help="defaults to DATABASE_URL / .env")
    ap.add_argument("--clean", default="data/clean")
    ap.add_argument("--sql", default="sql")
    a = ap.parse_args()
    run(a.url, a.clean, a.sql)
