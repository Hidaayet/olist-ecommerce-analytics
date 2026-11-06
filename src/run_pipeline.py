"""
One command to build the whole project from the raw CSVs.

    python -m src.run_pipeline                 # clean -> load -> views -> BI model -> segments -> checks -> figures
    python -m src.run_pipeline --analysis      # also run every query file in sql/03_analysis
    python -m src.run_pipeline --notebooks     # also re-execute notebooks 02 and 04
    python -m src.run_pipeline --report --author "Your Name"   # also rebuild the PDF report
    python -m src.run_pipeline --skip-clean    # reuse data/clean from a previous run

Prerequisites: PostgreSQL running, an EMPTY database named olist, and DATABASE_URL set
(environment variable or .env file, see .env.example). Raw CSVs in data/raw/.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

import psycopg2

from src import cleaning, config, db_load, make_figures
from src import segmentation as sg

ROOT = config.REPO_ROOT
SQL = ROOT / "sql"

# files that CREATE the views other steps depend on (order matters)
VIEW_FILES = [
    SQL / "03_analysis" / "00_base_views.sql",
    SQL / "03_analysis" / "05_cohorts_retention.sql",
    SQL / "03_analysis" / "06_customer_value.sql",
    SQL / "03_analysis" / "08_first_purchase_drivers.sql",
]
ANALYSIS_FILES = sorted((SQL / "03_analysis").glob("0[0-8]_*.sql"))
BI_FILE = SQL / "05_powerbi_model.sql"


def step(title: str):
    print(f"\n=== {title} " + "=" * max(3, 60 - len(title)))
    return time.time()


def run_sql_files(url: str, files):
    with psycopg2.connect(url) as conn:
        with conn.cursor() as cur:
            for f in files:
                t = time.time()
                cur.execute(f.read_text(encoding="utf-8"))
                print(f"  ran {f.relative_to(ROOT)}  ({time.time() - t:.1f}s)")


def reconcile(url: str):
    """Fail loudly if the database does not tie back to the cleaning step."""
    checks = {
        "orders = 99,441": ("SELECT COUNT(*) FROM olist.orders", 99441),
        "vw_order_facts is 1 row per order": ("SELECT COUNT(*) FROM olist.vw_order_facts", 99441),
        "sum(price) = 13,591,643.70": ("SELECT SUM(price) FROM olist.order_items", 13591643.70),
        "96,096 real customers": ("SELECT COUNT(DISTINCT customer_unique_id) FROM olist.customers", 96096),
        "dim_customer = 96,096 rows": ("SELECT COUNT(*) FROM olist_bi.dim_customer", 96096),
        "fact_orders = 99,441 rows": ("SELECT COUNT(*) FROM olist_bi.fact_orders", 99441),
        "fact_order_items = 112,650 rows": ("SELECT COUNT(*) FROM olist_bi.fact_order_items", 112650),
        "KPI revenue = 13,449,529.68": ("SELECT value FROM olist_bi.kpi_reference WHERE sort = 2", 13449529.68),
    }
    failed = []
    with psycopg2.connect(url) as conn, conn.cursor() as cur:
        for name, (query, expected) in checks.items():
            cur.execute(query)
            got = float(cur.fetchone()[0])
            ok = abs(got - expected) < 0.005
            print(f"  [{'PASS' if ok else 'FAIL'}] {name}  (got {got:,.2f})")
            if not ok:
                failed.append(name)
    if failed:
        raise SystemExit(f"Reconciliation failed: {failed}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--skip-clean", action="store_true")
    ap.add_argument("--analysis", action="store_true", help="run all analysis query files")
    ap.add_argument("--notebooks", action="store_true", help="re-execute notebooks 02 and 04")
    ap.add_argument("--report", action="store_true", help="rebuild the PDF executive report")
    ap.add_argument("--author", default="Portfolio project", help="name printed on the report")
    a = ap.parse_args()

    url = config.database_url()
    t0 = time.time()

    if not a.skip_clean:
        step("1/7 Clean raw CSVs (Python)")
        cleaning.run(ROOT / "data/raw", ROOT / "data/clean", verbose=False)
        print("  data/clean written, all hard validation checks passed")

    step("2/7 Create schema and load PostgreSQL")
    db_load.run(url, ROOT / "data/clean", SQL)

    step("3/7 Create analytical views")
    run_sql_files(url, ANALYSIS_FILES if a.analysis else VIEW_FILES)

    step("4/7 Create Power BI star schema (olist_bi)")
    run_sql_files(url, [BI_FILE])

    step("5/7 Compute and publish RFM segments")
    n = sg.publish_segments(sg.get_engine(url))
    print(f"  {n:,} customers written to olist.customer_segments")

    step("6/7 Reconcile database against the cleaning step")
    reconcile(url)

    step("7/7 Generate report figures")
    make_figures.main(sg.get_engine(url))

    if a.notebooks:
        step("Notebooks")
        for nb in ["02_cleaning.ipynb", "04_segmentation.ipynb"]:
            subprocess.run([sys.executable, "-m", "jupyter", "nbconvert", "--to", "notebook",
                            "--execute", "--inplace", str(ROOT / "notebooks" / nb)], check=True)
    if a.report:
        step("Executive report")
        from src import build_report
        build_report.main(["--author", a.author])

    print(f"\nDone in {time.time() - t0:.0f}s. Next: connect Power BI to schema olist_bi (see dashboards/BUILD_GUIDE.md).")


if __name__ == "__main__":
    main()
