# Run guide: from zero to finished project (Windows)

Total time: about 20 minutes of setup, then about 90 seconds for the pipeline.

## 0. What you need

| Tool | Version | Check |
|---|---|---|
| Python | 3.11 or newer | `python --version` |
| PostgreSQL | 14 or newer (with pgAdmin) | `Get-Service *postgres*` shows `Running` |
| Git + GitHub Desktop, VS Code | any recent | |
| Power BI Desktop | latest (Windows only) | only for the dashboard step |

VS Code extensions: **Python**, **Jupyter**, **SQLTools** (optional).

## 1. Get the code

Clone the repo with GitHub Desktop into a folder **outside OneDrive** (for example `C:\dev\olist-ecommerce-analytics`). OneDrive tries to sync the thousands of small files in `.venv` and the data files, which slows everything and can cause file-lock errors. Open the folder in VS Code (**File > Open Folder**) and use the integrated terminal (**Terminal > New Terminal**, PowerShell).

## 2. Python environment

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

The prompt should now start with `(.venv)`. If PowerShell refuses to run `Activate.ps1` ("running scripts is disabled"), run this once in the same window and activate again:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

In VS Code, press `Ctrl+Shift+P`, choose **Python: Select Interpreter**, and pick the `.venv` one (needed for the notebooks).

## 3. The data

Download the [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) from Kaggle (free account), unzip it, and put the **9 CSV files** in `data/raw/`:

```
olist_customers_dataset.csv          olist_order_reviews_dataset.csv
olist_geolocation_dataset.csv        olist_orders_dataset.csv
olist_order_items_dataset.csv        olist_products_dataset.csv
olist_order_payments_dataset.csv     olist_sellers_dataset.csv
product_category_name_translation.csv
```

## 4. The database

1. Open **pgAdmin**, connect to your server, right-click **Databases > Create > Database**, name it `olist` (leave it empty).
2. Copy the config template and put in your password:
   ```powershell
   Copy-Item .env.example .env
   notepad .env
   ```
   Edit the line so it reads (keep your own password and port):
   ```
   DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/olist
   ```
   The `.env` file is git-ignored, so the password never reaches GitHub. If your password contains `@ / : #`, URL-encode it (`@` becomes `%40`).

   **Which port?** The default is 5432. If you are not sure, run:
   ```powershell
   Get-Content "C:\Program Files\PostgreSQL\18\data\postgresql.conf" | Select-String "^port"
   ```
   (replace `18` with your version).

## 5. Build everything

```powershell
python -m src.run_pipeline
```

It runs seven steps and stops with a clear message if any check fails:

1. Clean the raw CSVs (20 validation checks)
2. Create the schema and load PostgreSQL (row counts compared to the CSVs)
3. Create the analytical views
4. Create the Power BI star schema (`olist_bi`)
5. Compute RFM segments and store them in the database
6. Reconcile the database against the cleaning step (revenue ties out to the cent)
7. Generate all report figures into `reports/figures/`

Expected end of the output: `Done in 90s` and eight `[PASS]` lines in step 6.

Useful options: `--analysis` (also run every query file), `--notebooks` (re-execute notebooks 02 and 04), `--report` (rebuild the PDF), `--skip-clean` (reuse `data/clean`).

## 6. Verify

```powershell
python -m pytest -q tests                      # 9 unit tests
```

In pgAdmin, open **Query Tool** on the `olist` database and run:

```sql
SELECT * FROM olist_bi.kpi_reference;          -- ten live KPIs
```

Revenue should read `13449529.68` and the late rate `8.13`. To run the project's SQL checks and every analysis query from the command line (needs `psql` on your PATH, see troubleshooting):

```powershell
psql -p 5432 -U postgres -d olist -f sql/04_validation.sql
psql -p 5432 -U postgres -d olist -f sql/03_analysis/run_all.sql
```

## 7. Explore the analysis

| What | Where |
|---|---|
| Advanced SQL (CTEs, window functions, cohorts, percentiles) | `sql/03_analysis/01_...` to `08_...` |
| Findings in plain language | `docs/analysis_findings.md`, `docs/phase4_findings.md` |
| Cleaning walkthrough and evidence | `notebooks/02_cleaning.ipynb` |
| Segmentation and retention | `notebooks/04_segmentation.ipynb` |
| Why each choice was made | `docs/decisions_log.md` |

To open a notebook in VS Code, double-click it, choose the `.venv` kernel, then **Run All**. The connection comes from your `.env` file.

## 8. Executive report

```powershell
python -m src.build_report --author "Your Name"
```

Output: `reports/Olist_Executive_Report.pdf` (7 pages). A ready-made copy is already in the repo.

## 9. Power BI dashboard

Follow `dashboards/BUILD_GUIDE.md` (60 to 90 minutes). Check your cards against `dashboards/expected_values.md`. Save screenshots of each page into `reports/dashboard_screenshots/`, export a `.pbit` template, and add the screenshots to the README. Do not commit the `.pbix`, which embeds the dataset.

## 10. Publish to GitHub

In GitHub Desktop you should see only code, SQL, notebooks, docs, reports and dashboards files. `data/raw`, `data/clean`, `.env` and `*.pbix` must **not** appear (the `.gitignore` excludes them). Suggested commits:

1. `Add cleaning pipeline and validation`
2. `Add PostgreSQL schema, loaders and base views`
3. `Add advanced SQL analysis`
4. `Add segmentation, retention and tests`
5. `Add Power BI model, measures and build guide`
6. `Add executive report and documentation`

Then **Publish repository**. Add a short description and the topics `sql`, `postgresql`, `python`, `power-bi`, `data-analysis`, `e-commerce`.

## Troubleshooting (problems we actually hit)

| Symptom | Cause and fix |
|---|---|
| `Connection refused` on port 5432 | PostgreSQL is not running, or listens on another port. `Get-Service *postgres*` (start it with `Start-Service <name>`), then read the real port from `postgresql.conf`, and put it in `.env`. |
| You edited `postgresql.conf` but the port did not change | (1) `postgresql.auto.conf` in the same folder overrides it: edit the `port` line there too. (2) The edit needs an **Administrator** PowerShell for both Notepad and `Restart-Service`. |
| `No module named 'src'` | You are not in the repo root, or you ran a file directly. `cd` to the project folder and use `python -m src.run_pipeline`. |
| `No module named pandas` (or psycopg2) | The virtual environment is not active, or you ran the system Python. The prompt must start with `(.venv)`. |
| `$env:DATABASE_URL` / `set` confusion | Skip both: put the URL in `.env`. (`set VAR=...` does nothing in PowerShell.) |
| `database "olist" does not exist` | Connection works. Create the empty database in pgAdmin (step 4). |
| `password authentication failed` | Wrong password in `.env`, or special characters not URL-encoded. |
| `psql` is not recognised | Add `C:\Program Files\PostgreSQL\18\bin` to your PATH, or paste the SQL files into pgAdmin's Query Tool instead. |
| `Run python -m src.cleaning first. Missing: [...]` | Raw CSVs missing from `data/raw`, or the cleaning step was skipped. |
| Raw CSV not found | File names must match exactly (step 3). |
| Slow or locked files | The project folder is inside OneDrive. Move it to `C:\dev`. |
| `pip install sql` in a tutorial | Do not. That is an unrelated package. This project needs only `requirements.txt`. |
| Power BI asks for Npgsql | Install the provider from the dialog link and restart Power BI. |
