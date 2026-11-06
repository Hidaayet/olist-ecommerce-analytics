"""
Phase 6 - Build the executive report PDF.

    python -m src.build_report [--author "Your Name"]

Needs the figures in reports/figures (python -m src.make_figures). All numbers in the
text were measured on the PostgreSQL model; see docs/analysis_findings.md and
docs/phase4_findings.md for the queries behind them.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (Image, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

ROOT = Path(__file__).resolve().parent.parent
FIG = ROOT / "reports" / "figures"
OUT = ROOT / "reports" / "Olist_Executive_Report.pdf"

NAVY = colors.HexColor("#1f4e79")
LIGHT = colors.HexColor("#eef3f8")
ORANGE = colors.HexColor("#d9822b")
GREY = colors.HexColor("#5a5a5a")

ss = getSampleStyleSheet()
BODY = ParagraphStyle("body", parent=ss["Normal"], fontName="Helvetica", fontSize=9.5, leading=13.5,
                      alignment=TA_LEFT, spaceAfter=4)
SMALL = ParagraphStyle("small", parent=BODY, fontSize=8, leading=10.5, textColor=GREY)
CELL = ParagraphStyle("cell", parent=BODY, fontSize=8.3, leading=10.8, spaceAfter=0)
CELLB = ParagraphStyle("cellb", parent=CELL, fontName="Helvetica-Bold")
CELLW = ParagraphStyle("cellw", parent=CELL, fontName="Helvetica-Bold", textColor=colors.white)
H1 = ParagraphStyle("h1", parent=ss["Heading1"], fontName="Helvetica-Bold", fontSize=15, textColor=NAVY,
                    spaceBefore=6, spaceAfter=6)
H2 = ParagraphStyle("h2", parent=ss["Heading2"], fontName="Helvetica-Bold", fontSize=11.5, textColor=NAVY,
                    spaceBefore=8, spaceAfter=4)
TITLE = ParagraphStyle("title", parent=ss["Title"], fontName="Helvetica-Bold", fontSize=22, leading=26,
                       textColor=NAVY, alignment=TA_LEFT, spaceAfter=4)
SUB = ParagraphStyle("sub", parent=BODY, fontSize=11, textColor=GREY, spaceAfter=10)
SOWHAT = ParagraphStyle("sowhat", parent=BODY, fontSize=9.3, backColor=LIGHT, borderPadding=(5, 6, 5, 6),
                        leftIndent=6, rightIndent=6, spaceBefore=4, spaceAfter=10)
KPI_N = ParagraphStyle("kpin", parent=BODY, fontName="Helvetica-Bold", fontSize=12.5, textColor=NAVY,
                       alignment=1, spaceAfter=0, leading=18)
KPI_L = ParagraphStyle("kpil", parent=SMALL, alignment=1, spaceAfter=0)


def P(text, style=BODY):
    return Paragraph(text, style)


def bullets(items, style=BODY):
    return [Paragraph(f"&bull;&nbsp; {t}", ParagraphStyle("b", parent=style, leftIndent=12, firstLineIndent=-10,
                                                          spaceAfter=2.5)) for t in items]


def fig(name, width_cm=16.5):
    path = FIG / name
    w, h = PILImage.open(path).size
    width = width_cm * cm
    return Image(str(path), width=width, height=width * h / w)


def tbl(data, col_widths, header=True, zebra=True, extra=None):
    t = Table(data, colWidths=col_widths, repeatRows=1 if header else 0)
    style = [("VALIGN", (0, 0), (-1, -1), "TOP"),
             ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
             ("TOPPADDING", (0, 0), (-1, -1), 3.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
             ("LINEBELOW", (0, 0), (-1, -1), 0.25, colors.HexColor("#cfd8e3"))]
    if header:
        style += [("BACKGROUND", (0, 0), (-1, 0), NAVY)]
    if zebra:
        style += [("ROWBACKGROUNDS", (0, 1 if header else 0), (-1, -1), [colors.white, LIGHT])]
    t.setStyle(TableStyle(style + (extra or [])))
    return t


def kpi_strip():
    items = [("R$13.45M", "revenue, 20 months"), ("97,910", "orders"), ("R$137", "average order value"),
             ("8.1%", "orders delivered late"), ("4.12 / 5", "average review score"),
             ("3.0%", "customers who ever reorder")]
    row1 = [[P(n, KPI_N), ] for n, _ in items]
    cells = [[Table([[P(n, KPI_N)], [P(l, KPI_L)]], colWidths=[2.75 * cm]) for n, l in items]]
    t = Table(cells, colWidths=[2.85 * cm] * 6)
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), LIGHT), ("BOX", (0, 0), (-1, -1), 0.5, NAVY),
                           ("LINEAFTER", (0, 0), (-2, -1), 0.5, colors.white),
                           ("TOPPADDING", (0, 0), (-1, -1), 7), ("BOTTOMPADDING", (0, 0), (-1, -1), 7)]))
    return t


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(GREY)
    canvas.drawString(2 * cm, 1.2 * cm, "Olist E-commerce Business Intelligence | Executive report")
    canvas.drawRightString(A4[0] - 2 * cm, 1.2 * cm, f"Page {doc.page}")
    canvas.restoreState()


def build(author: str = "Portfolio project"):
    doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=2 * cm, rightMargin=2 * cm, topMargin=1.8 * cm,
                            bottomMargin=1.8 * cm, title="Olist E-commerce: Executive Report", author=author)
    s = []

    # ------------------------------------------------------------------ page 1
    s += [P("Olist E-commerce: Business Intelligence and Customer Analytics", TITLE),
          P(f"Executive report | Brazilian marketplace, January 2017 to August 2018 | Prepared by {author}", SUB),
          kpi_strip(), Spacer(1, 10), P("Executive summary", H1),
          P("Olist is a Brazilian marketplace that connects small sellers with customers. We analysed about 100,000 real "
            "orders to understand how revenue evolves, what drives customer satisfaction, and where the business can "
            "improve. Five findings matter most:")]
    s += bullets([
        "<b>Growth has stalled.</b> Revenue in January to August 2018 was 2.4 times the same months of 2017, but "
        "monthly revenue has sat between R$0.84M and R$0.99M since January 2018. Growth came from more orders, not "
        "bigger baskets (average order value stayed near R$137).",
        "<b>Late delivery is the strongest driver of unhappy customers.</b> Late orders average a 2.57 review against "
        "4.29 for on-time orders, and 54% of them receive 1 or 2 stars (9% for on-time). Satisfaction collapses once "
        "an order is more than 3 days late.",
        "<b>The problem is geographic and seasonal.</b> North and north-east customers wait longer and are late 13.6% "
        "of the time, against 7.4% elsewhere. Late rates peaked at 14% to 21% in the November 2017 and February to "
        "March 2018 demand peaks.",
        "<b>Almost nobody comes back.</b> 97% of customers bought once. Only about 1.9% reorder within 180 days, and "
        "that barely depends on category, order value or payment type.",
        "<b>Revenue is concentrated.</b> 8 of 74 categories deliver half of revenue, and the top 10% of customers "
        "deliver 41% (all of the large segments are one-time buyers).",
    ])
    s += [P("What we recommend", H2)]
    s += bullets([
        "<b>Fix delivery first:</b> realistic delivery estimates and a carrier plan for the north and north-east, "
        "plus capacity planning ahead of demand peaks. This is the clearest lever on reviews.",
        "<b>Treat retention as a cheap experiment, not a strategy:</b> test win-back offers on a holdout group. Even a "
        "doubled repeat rate would add under 1% to revenue (see the sizing in section 7).",
        "<b>Shift attention to acquisition and mix:</b> growth now depends on winning new customers, which this dataset "
        "cannot measure. Add channel and acquisition-cost data to the next analysis.",
    ])
    s += [P("All figures are measured on the cleaned dataset. Recommendations and impact sizes are hypotheses to be "
            "tested, not predictions: this is observational data without marketing, pricing or competitor information.",
            SMALL), PageBreak()]

    # ------------------------------------------------------------------ revenue
    s += [P("1. Revenue: strong growth, then a plateau", H1), fig("fig01_revenue_trend.png", 14.5)]
    s += bullets([
        "Revenue peaked at R$1.00M in November 2017 (+52% on the month, coinciding with Black Friday). Since January "
        "2018 it has ranged from R$838k to R$994k, and August 2018 (R$849k) is about 15% below April.",
        "Orders per month have been flat in 2018 (6,100 to 7,200). Average order value (R$137) and items per order "
        "(about 1.1) barely moved, so the lever is the number of customers, not basket size.",
        "Sao Paulo generates 38.3% of revenue, and Sao Paulo, Rio de Janeiro and Minas Gerais together 63%.",
    ])
    s += [fig("fig02_category_pareto.png", 13.5), P("2. Categories: a concentrated catalogue", H2)]
    s += bullets([
        "18 of 74 categories generate 80% of revenue and 8 generate half. The top five are health_beauty (9.3%), "
        "watches_gifts (8.9%), bed_bath_table (7.7%), sports_leisure (7.3%) and computers_accessories (6.7%).",
        "The biggest gainers, January to August 2018 against 2017, are health_beauty (+R$523k, +211%) and "
        "watches_gifts (+R$502k, +243%).",
        "Quality varies: office_furniture has the lowest average review (3.50, 26% of reviews at 1 or 2 stars) and "
        "bed_bath_table, the third largest category, scores only 3.90.",
    ])
    s += [P("<b>So what:</b> revenue growth was driven by order volume and has levelled off. Category and customer mix "
            "decisions should focus on a small number of winners.", SOWHAT), PageBreak()]

    # ------------------------------------------------------------------ delivery
    s += [P("3. Delivery: slow in the north, stressed at peaks", H1), fig("fig03_delivery_by_state.png", 14.5)]
    s += bullets([
        "Typical delivery takes 10.2 days (median) and 23 days at the 90th percentile. Olist promises 23.6 days on "
        "average, so on-time orders arrive about 13 days early. 8.1% of orders arrive late, by 9.5 days on average.",
        "The carrier leg is the bottleneck: about 80% of delivery time (median 7.1 days) is between carrier pick-up "
        "and the customer. Order approval takes minutes, and hand-over to the carrier takes 1.8 days.",
        "Alagoas has a median of 22.3 days and 24% late orders, against 7.2 days and 5.9% in Sao Paulo. Rio de "
        "Janeiro stands out: transit is moderate (12.0 days) but 13.5% of orders are late.",
        "Orders shipped across states take a median of 12.8 days against 6.6 for same-state orders, and carry "
        "34.8% freight against 23.8%. 71% of all items ship from Sao Paulo sellers.",
    ])
    s += [fig("fig04_late_rate_monthly.png", 14.5)]
    s += bullets([
        "Late deliveries hit 14.3% in November 2017, 16.0% in February 2018 and 21.4% in March 2018, so the network "
        "struggles during demand peaks.",
        "Caveat: delivery times for July and August 2018 look faster mainly because slow orders had not yet been "
        "delivered when the data was captured. Do not read them as an improvement.",
    ])
    s += [PageBreak()]

    # ------------------------------------------------------------------ reviews
    s += [P("4. Delays and reviews: the cliff at three days", H1), fig("fig05_delay_vs_review.png", 15)]
    s += bullets([
        "Average review is 4.29 for on-time orders and 2.57 for late orders. 1 and 2 star reviews are 9% of on-time "
        "orders and 54% of late orders.",
        "Satisfaction falls gradually, then sharply: 3.77 at 1 to 3 days late, 2.32 at 3 to 7 days late and 1.73 "
        "beyond 7 days.",
        "38% of all 1-star reviews follow a late delivery, although only 8% of orders are late.",
        "The promise matters as well as the wait: in the 21 to 30 day band, on-time orders score 3.96 and late orders 2.84.",
    ])
    s += [P("<b>So what:</b> a one-to-three-day delay is tolerable. A week's delay destroys the review. Setting "
            "honest delivery dates in slow regions protects reviews at the cost of some conversion. This is an "
            "association in observational data, since late orders may also be harder shipments.", SOWHAT)]

    # ------------------------------------------------------------------ customers
    s += [P("5. Customers: valuable, but one-time", H1), fig("rfm_segments.png", 14.5)]
    s += bullets([
        "The three big-spender segments (new, at-risk and mid-age) are 38% of customers and 71% of revenue, and "
        "<b>every one of them has bought only once</b>. Repeat buyers are 3% of customers and 6% of revenue.",
        "The top 10% of customers generate 41% of revenue, the top 20% generate 57%.",
        "Statistical clustering (K-means) found no structure beyond these rules, so the segments are not hiding a "
        "better grouping. Spend tiers are a business choice, not a natural split.",
    ])
    s += [PageBreak(), P("6. Retention: low everywhere", H1), fig("cohort_heatmap.png", 11.5)]
    s += bullets([
        "Fewer than 1% of customers return in any month after their first order, and the pattern is the same across "
        "all cohorts from January 2017 to February 2018.",
        "The overall 180-day repeat rate is 1.89%. It ranges from 1.0% (cool_stuff) to 2.9% (fashion_bags_accessories) "
        "by first-purchase category, which is a real but small difference.",
        "The idea that customers simply buy one-off categories is <b>not supported</b>: durable categories such as "
        "bed_bath_table (2.5%) and furniture_decor sit above average.",
        "First-order experience has a small effect: customers who gave 5 stars reorder at 2.05% against 1.54% after "
        "1 star. Order value and payment type show no effect.",
    ])
    s += [PageBreak()]

    # ------------------------------------------------------------------ recommendations
    s += [P("7. Recommendations and sizing", H1),
          P("Ordered by priority. Impact sizes are illustrative upper bounds or scenarios, with assumptions stated. "
            "Each should be validated with a controlled test before scaling.")]
    rows = [[P("#", CELLW), P("Recommendation", CELLW), P("Evidence", CELLW), P("How to test / size", CELLW),
             P("Priority", CELLW)],
            [P("1", CELLB), P("<b>Realistic delivery estimates and a carrier plan for the north and north-east</b>", CELL),
             P("Late orders score 2.57 vs 4.29. North and north-east: 13.6% late vs 7.4% elsewhere, reviews 3.98 vs 4.18.", CELL),
             P("A/B test padded estimates in two states. If the north/north-east late rate matched the rest of Brazil, "
               "about 670 fewer late orders over the period. Upper bound if no order were late: average review "
               "4.16 to 4.30.", CELL), P("High", CELLB)],
            [P("2", CELLB), P("<b>Capacity plan before demand peaks</b> (Black Friday, Q1)", CELL),
             P("Late rate 14.3%, 16.0% and 21.4% in Nov 2017, Feb and Mar 2018, against 8.1% on average.", CELL),
             P("Agree carrier capacity and seller dispatch limits in advance. Track a leading indicator: share of "
               "orders not handed to the carrier within 2 days.", CELL), P("High", CELLB)],
            [P("3", CELLB), P("<b>Recruit sellers outside Sao Paulo</b>", CELL),
             P("71% of items ship from Sao Paulo. Cross-state orders: 12.8 vs 6.6 days, 34.8% vs 23.8% freight.", CELL),
             P("Pilot seller recruitment (or a regional hub) in one region. Measure delivery time and freight share "
               "against a comparable region.", CELL), P("Medium", CELLB)],
            [P("4", CELLB), P("<b>Quality programme for large, low-rated categories</b>", CELL),
             P("bed_bath_table: 7.7% of revenue, review 3.90. office_furniture: review 3.50, 26% at 1-2 stars.", CELL),
             P("Seller scorecards, listing standards (photos, sizes, descriptions), early warning on sellers with "
               "falling scores.", CELL), P("Medium", CELLB)],
            [P("5", CELLB), P("<b>Shift focus to acquisition and category mix</b>; add channel and cost data", CELL),
             P("Revenue flat since Jan 2018 (R$0.84M to R$0.99M a month); orders and basket size flat; retention "
               "about 2%.", CELL),
             P("Extend the analysis with acquisition channel, cost per customer and conversion. Prioritise "
               "health_beauty and watches_gifts, the fastest growing categories.", CELL), P("Medium", CELLB)],
            [P("6", CELLB), P("<b>Win-back test with a holdout group</b>", CELL),
             P("14,015 at-risk big spenders, R$3.9M past revenue, 1.9% repeat rate.", CELL),
             P("Scenario: lifting the 180-day repeat rate by 2 points adds about 280 orders, i.e. R$38k at the average "
               "order (R$137) up to R$78k at their past spend (R$278). That is under 1% of revenue.", CELL),
             P("Low", CELLB)],
            [P("7", CELLB), P("<b>Fix timestamp logging</b> (carrier hand-over)", CELL),
             P("189 orders have impossible timestamps, 158 of them in May to Aug 2018.", CELL),
             P("Audit how carrier events are recorded. Low effort, protects delivery KPIs.", CELL), P("Low", CELLB)]]
    s += [tbl(rows, [0.7 * cm, 4.3 * cm, 4.6 * cm, 5.9 * cm, 1.5 * cm]), Spacer(1, 8),
          P("<b>Reading the retention sizing.</b> The win-back scenario shows why loyalty programmes are not the "
            "first priority here: even a doubling of an already-low repeat rate is small next to R$13.4M of revenue. "
            "Reducing late deliveries and acquiring customers more efficiently have far more headroom.", SOWHAT),
          PageBreak()]

    # ------------------------------------------------------------------ method
    s += [P("8. Method, data quality and limitations", H1), P("Data and scope", H2)]
    s += bullets([
        "Source: Brazilian E-Commerce Public Dataset by Olist (Kaggle, CC BY-NC-SA 4.0): 99,441 orders, 112,650 order "
        "lines, 96,096 real customers, 3,095 sellers, 32,951 products. Analysis window: January 2017 to August 2018, "
        "because late 2016 and the last months of 2018 are sparse.",
        "Revenue is the sum of item prices on valid sales (canceled and unavailable orders excluded), excluding "
        "freight. Delivery metrics use delivered orders only. Late means delivered after the estimated date.",
    ])
    s += [P("Data traps handled", H2)]
    s += bullets([
        "<b>customer_id is not a person.</b> Olist creates a new ID per order. Using the real identifier "
        "(customer_unique_id) is what reveals that 97% of customers buy once.",
        "<b>Join fan-out.</b> Joining items to payments row by row inflates revenue by 4.5% (R$14.21M instead of "
        "R$13.59M). All analysis aggregates first, in a fan-out-safe view.",
        "<b>Reviews:</b> 547 orders had several reviews; the latest is kept (one per order). <b>Geolocation:</b> 1M "
        "rows collapsed to one per zip prefix. <b>Zip codes</b> kept as text to preserve leading zeros.",
        "Suspicious records are flagged, not deleted. Python validation (20 checks) and SQL reconciliation both pass, and "
        "the database ties back to the cleaning step to the cent. Several issues found during the project (a float-comparison bug, a NULL-averaging bug, a slow view) were fixed and "
        "documented in the decisions log.",
    ])
    s += [P("Limitations", H2)]
    s += bullets([
        "Observational data: associations (for example delay and reviews) are not proof of cause.",
        "No marketing, pricing, cost or competitor data, so profitability and acquisition cost cannot be assessed.",
        "Delivery times in the last two months are optimistic, because slow orders had not yet arrived.",
        "Retention is measured on customer_unique_id, which can miss people who registered under several identities.",
        "Repeat rates are low, so subgroup estimates carry wide confidence intervals (shown in the notebook).",
        "Impact sizes in section 7 are scenarios with stated assumptions, not forecasts.",
    ])
    s += [P("Reproducibility", H2),
          P("Everything is reproducible from the raw CSVs with one command (<font name='Courier'>python -m "
            "src.run_pipeline</font>). The repository contains the cleaning pipeline, PostgreSQL schema, all SQL, "
            "notebooks, the Power BI model and measures, and the decisions log with the evidence behind every choice.")]
    doc.build(s, onFirstPage=footer, onLaterPages=footer)
    print(f"Report written to {OUT}")


def main(argv=None):
    """argv=None reads sys.argv; pass a list (even empty) to call from other code."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--author", default="Portfolio project")
    build(ap.parse_args(argv).author)


if __name__ == "__main__":
    main()
