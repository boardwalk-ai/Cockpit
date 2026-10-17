"""Builds docs/pricing/study-studio-proposed-pricing.pdf: the proposed credit
prices and plan economics for Study Studio, from the benchmark results in
docs/pricing/data (bench.py output) and the draft plans from Finance.

    python docs/pricing/make_pricing_proposal.py
"""
import json
import math
import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
OUT = os.path.join(HERE, "study-studio-proposed-pricing.pdf")
DATE = "9 October 2026"

runs = {k: json.load(open(os.path.join(DATA, f"{k}.json"), encoding="utf-8"))
        for k in ["b1-flashlite", "b1-glm", "b2-flashlite", "b2-glm"]}

# ---------------------------------------------------------------- styles ---
ss = getSampleStyleSheet()
INK, MUTED, ACCENT, LINE, SOFT, GOOD, BAD = (colors.HexColor(h) for h in
                                             ("#1b1a19", "#6b6660", "#C4122A", "#d9d4cc", "#f5f2ec", "#1d6b3a", "#a3121f"))
H1 = ParagraphStyle("H1", parent=ss["Title"], fontName="Helvetica-Bold", fontSize=22, leading=26, textColor=INK, alignment=TA_LEFT, spaceAfter=4)
H2 = ParagraphStyle("H2", parent=ss["Heading2"], fontName="Helvetica-Bold", fontSize=13.5, leading=17, textColor=INK, spaceBefore=14, spaceAfter=6)
H3 = ParagraphStyle("H3", parent=ss["Heading3"], fontName="Helvetica-Bold", fontSize=10.5, leading=13, textColor=INK, spaceBefore=8, spaceAfter=3)
P = ParagraphStyle("P", parent=ss["BodyText"], fontName="Helvetica", fontSize=9.2, leading=12.6, textColor=INK, spaceAfter=5)
BUL = ParagraphStyle("B", parent=P, leftIndent=12, bulletIndent=2, spaceAfter=3)
SMALL = ParagraphStyle("S", parent=P, fontSize=7.8, leading=10, textColor=MUTED)
CELL = ParagraphStyle("C", parent=P, fontSize=8, leading=10, spaceAfter=0)
CELLB = ParagraphStyle("CB", parent=CELL, fontName="Helvetica-Bold")
NOTE = ParagraphStyle("N", parent=P, backColor=SOFT, borderPadding=(6, 7, 6, 7), leftIndent=7, rightIndent=7, spaceBefore=4, spaceAfter=9)
FORMULA = ParagraphStyle("F", parent=NOTE, fontName="Helvetica-Bold", fontSize=10, leading=14, alignment=1)


def c(x, bold=False):
    return Paragraph(str(x), CELLB if bold else CELL)


def table(rows, widths, zebra=True, bold_rows=()):
    data = [[c(v, bold=i == 0 or i in bold_rows) for v in r] for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1)
    st = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, 0), 0.8, INK),
          ("LINEBELOW", (0, 1), (-1, -1), 0.25, LINE), ("TOPPADDING", (0, 0), (-1, -1), 3.5),
          ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5), ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4)]
    if zebra:
        for i in range(2, len(rows), 2):
            st.append(("BACKGROUND", (0, i), (-1, i), SOFT))
    t.setStyle(TableStyle(st))
    return t


def bullets(items):
    return [Paragraph(x, BUL, bulletText="•") for x in items]


def usd(x, d=2):
    return f"-${-x:,.{d}f}" if x < 0 else f"${x:,.{d}f}"


def signed(x, d=2):
    col = "#1d6b3a" if x >= 0 else "#a3121f"
    return f"<font color='{col}'><b>{'+' if x >= 0 else '-'}${abs(x):,.{d}f}</b></font>"


def pct(x):
    return f"{x * 100:.0f}%"


# ------------------------------------------------- measured AI costs ($) ---
def avg(xs):
    xs = list(xs)
    return sum(xs) / len(xs)


ask_calls = [r["steps"]["ask"] for r in runs.values()]
ASK = sum(a["costUsd"] for a in ask_calls) / sum(a["calls"] for a in ask_calls)
gr = [r["steps"]["grade"] for r in runs.values()]
GRADE = sum(g["costUsd"] for g in gr) / sum(g["calls"] for g in gr)
STD_TYP = avg(runs[k]["build"]["usage"]["costUsd"] for k in ("b1-flashlite", "b2-flashlite"))
DEEP_TYP = avg(runs[k]["build"]["usage"]["costUsd"] for k in ("b1-glm", "b2-glm"))
STD_HIGH, DEEP_HIGH = 0.087, 0.079      # large upload that fills the 120k-character outline (cost sheet, section 6)
CONCEPT_TYP, CONCEPT_HIGH = 0.017, 0.025  # concept map for one lesson (cost sheet, section 5)

# ---------------------------------------------------------- revenue side ---
STRIPE_PCT, STRIPE_FIX, BILLING_PCT = 0.029, 0.30, 0.007  # card fee per charge; Stripe Billing on subscriptions


def net_sub(price):  # one subscription charge after Stripe card + Billing fees
    return price - price * (STRIPE_PCT + BILLING_PCT) - STRIPE_FIX


def net_pack(price):
    return price - price * STRIPE_PCT - STRIPE_FIX


PRO_CR, PRO_PROMO, PREM_CR, FREE_CR = 1000, 1000, 5000, 500
plans = [  # name, billing, list price, net per month, credits per month
    ("Pro", "monthly (launch)", "$4.99/mo", net_sub(4.99), PRO_CR + PRO_PROMO),
    ("Pro", "yearly (launch)", "$49.99/yr", net_sub(49.99) / 12, PRO_CR + PRO_PROMO),
    ("Pro", "monthly (later)", "$9.99/mo", net_sub(9.99), PRO_CR + PRO_PROMO),
    ("Premium", "monthly (launch)", "$9.99/mo", net_sub(9.99), PREM_CR),
    ("Premium", "yearly (launch)", "$99.99/yr", net_sub(99.99) / 12, PREM_CR),
    ("Premium", "monthly (later)", "$19.99/mo", net_sub(19.99), PREM_CR),
]
packs = [(1000, 9.99), (5000, 39.99)]
V_MIN = min(p[3] / p[4] for p in plans)  # the cheapest credit we sell
AI_SHARE = 0.30
MAX_AI_PER_CREDIT = AI_SHARE * V_MIN


def nice(x):  # round a raw credit price up to a round number
    for step in (5, 10, 25, 50):
        if x <= step * 10:
            return int(math.ceil(x / step) * step)
    return int(math.ceil(x / 50) * 50)


actions = [  # name, key, typical $, high $, proposed credits, note
    ("Ask AI (one answer)", "study_price_ask", ASK, ASK, 20, "Claude Sonnet 4.6 today"),
    ("Standard build (one studio)", "study_price_build", STD_TYP, STD_HIGH, 150, "Gemini 3.1 Flash Lite, ~20 s"),
    ("Deep build (one studio)", "study_price_build_deep *", DEEP_TYP, DEEP_HIGH, 200, "GLM 5.3 Flash, 6-7 min, 2-3x more lessons"),
    ("Concept map (one lesson)", "study_price_concepts", CONCEPT_TYP, CONCEPT_HIGH, 50, "older studios only; new builds include it"),
    ("Recall grading (one spoken answer)", "study_price_grade", GRADE, GRADE, 0, "free: would drain a recall session otherwise"),
]
WORST_PER_CREDIT = max(hi / cr for _, _, _, hi, cr, _ in actions if cr)
ASK_PER_CREDIT = ASK / 20

# ------------------------------------------------------------- document ---
story = []
A = story.append
A(Paragraph("Study Studio — Proposed Pricing Structure", H1))
A(Paragraph(f"Credit prices and plan economics · {DATE} · Study Studio only (OctoNotes is priced separately) · "
            "companion to the AI Cost Sheet of 8 October 2026", SMALL))
A(Spacer(1, 8))

# 1 -------------------------------------------------------------------------
A(Paragraph("1. Summary", H2))
A(Paragraph(
    "The draft plans from Finance (Free / Pro / Premium, their prices and their monthly credit allowances) are kept as they are. "
    "What changes is <b>how many credits each AI action costs</b>, and the rule we use to set those prices.", P))
story += bullets([
    "<b>Price every action in credits from one rule:</b> even if a user spends every credit on the most expensive action, "
    f"AI must cost at most <b>{pct(AI_SHARE)} of the money we receive</b>. The other {pct(1 - AI_SHARE)} pays for servers, free users and profit.",
    "<b>Proposed prices:</b> Ask AI <b>20</b> · Standard build <b>150</b> · Deep build <b>200</b> · Concept map <b>50</b> · Recall grading <b>free</b>.",
    "<b>Every paid plan keeps 64-88% of its net revenue</b> after the worst-case AI bill, before servers. "
    "At typical use (about 30% of the allowance) AI is 3-9% of revenue.",
    "<b>Replace the line \"100 OctoCredits = about $1 of AI cost\".</b> Measured, an AI action costs $0.009-0.09, not $1. "
    "If a developer implemented that rate literally (1 credit = 1 cent of AI), every plan would lose money.",
    "<b>Replace \"cost + 10%, rounded up to the next dollar, minimum 100 credits\".</b> It only works because of the minimum, "
    "it makes every action cost the same 100 credits, and it gives a Free user 5 actions a month.",
    "<b>Remove \"larger OctoNotes/transcription usage\" from Premium</b> in this sheet; OctoNotes gets its own pricing.",
])

# 2 -------------------------------------------------------------------------
A(Paragraph("2. What the current draft does, and why it needs to change", H2))
A(Paragraph(
    "The draft sets prices by cost-plus: run a feature 10 times, take the average AI cost, add 10%, round up to the next whole "
    "dollar, and charge 100 credits per dollar, with a minimum of 100 credits per AI action.", P))
rows = [["Draft rule", "What actually happens", "Fix"],
        ["100 credits = about $1 of AI cost",
         f"An Ask AI answer costs ${ASK:.4f}; a full studio build ${STD_TYP:.3f}. 100 credits buy 1-9 cents of AI, not $1.",
         "Drop the table. A credit's value comes from what users pay for it (section 4)."],
        ["Cost + 10%, round up to the next dollar",
         "Every action costs well under $1, so every action rounds up to $1 = 100 credits. The real markup is 10-100x, not 10%.",
         "Fixed credit price per action, set from the 30% rule (section 5)."],
        ["Minimum 100 credits per action",
         "Profitable, but Free = 5 actions a month and Pro = 20. Recall grading ($0.00005) would cost 100 credits per spoken answer.",
         "Small actions cost few credits; grading is free."],
        ["Premium: larger OctoNotes/transcription usage",
         "Not part of Study Studio; transcription is billed per audio minute and is not measured here.",
         "Remove from this sheet; price OctoNotes separately."],
        ["Promo +1,000 credits on Pro",
         "Doubles Pro's allowance and its worst-case AI bill for as long as it runs.",
         "Give it for the first 3 months only (section 8)."]]
A(table(rows, [1.6 * inch, 3.0 * inch, 2.4 * inch]))
A(Paragraph(
    "Under the draft as written we do <b>not</b> lose money on the Study Studio features measured so far, but only because of "
    "the 100-credit minimum. The stated reasoning (\"about $1 of AI\") is wrong by 10-100x, and anyone pricing a new "
    "feature from it would price it wrongly.", NOTE))

# 3 -------------------------------------------------------------------------
A(Paragraph("3. Measured AI cost per action", H2))
A(Paragraph(
    "From the production benchmark (AI Cost Sheet, 8 October 2026): real studios built in the live app with thinking off, "
    "cost taken from OpenRouter's own usage reports. \"Large\" is an upload big enough to fill the 120,000-character outline "
    "limit — the most a single build can cost today.", P))
rows = [["Action", "Model", "Typical cost", "Large / worst"]]
for name, _, typ, hi, _, note in actions:
    model = {"Ask": "Claude Sonnet 4.6", "Deep": "GLM 5.3 Flash"}.get(name.split()[0], "Gemini 3.1 Flash Lite")
    rows.append([name, model,
                 usd(typ, 5 if typ < 0.001 else 4), usd(hi, 5 if hi < 0.001 else 4)])
A(table(rows, [2.3 * inch, 2.5 * inch, 1.1 * inch, 1.1 * inch]))
A(Paragraph("Ingesting uploads (text extraction, OCR, embeddings) runs on our own server and has no per-call AI cost; it is part of server cost.", SMALL))

# 4 -------------------------------------------------------------------------
A(Paragraph("4. What one credit is worth", H2))
A(Paragraph(
    "A credit is worth what the user paid for it, after payment fees, divided by the credits they get. Plan credits are much "
    "cheaper than pack credits, so prices must be safe at the <b>cheapest</b> credit we sell.", P))
A(Paragraph(f"Fees assumed: Stripe card {STRIPE_PCT * 100:.1f}% + ${STRIPE_FIX:.2f} per charge, plus Stripe Billing "
            f"{BILLING_PCT * 100:.1f}% on subscriptions. Pro counts its {PRO_PROMO:,} promotional credits.", SMALL))
rows = [["Plan", "Billing", "Price", "Net per month", "Credits / month", "Value of 1 credit"]]
for name, bill, price, net, cr in plans:
    rows.append([name, bill, price, usd(net), f"{cr:,}", usd(net / cr, 5)])
for n, p in packs:
    rows.append(["Credit pack", "one-off", usd(p), usd(net_pack(p)) + " (once)", f"{n:,}", usd(net_pack(p) / n, 5)])
rows.append(["Free", "—", "$0", "$0", f"{FREE_CR:,}", "$0 (we pay)"])
A(table(rows, [0.9 * inch, 1.2 * inch, 0.85 * inch, 1.3 * inch, 1.1 * inch, 1.65 * inch]))
A(Paragraph(f"The cheapest credit is Premium yearly at about <b>{usd(V_MIN, 5)}</b>. A pack credit is worth about 5x more, "
            "which is why prices set from pack value (as in the first cost sheet) would lose money on heavy plan users.", NOTE))

# 5 -------------------------------------------------------------------------
A(Paragraph("5. The pricing rule", H2))
A(Paragraph(f"Worst-case AI cost may use at most {pct(AI_SHARE)} of the value of the cheapest credit:", P))
A(Paragraph(f"Credits per action = largest AI cost of the action ÷ ({pct(AI_SHARE)} × {usd(V_MIN, 5)}) "
            f"= largest AI cost ÷ {usd(MAX_AI_PER_CREDIT, 5)}", FORMULA))
A(Paragraph(
    f"{pct(AI_SHARE)} is a common ceiling for the AI share of revenue in AI apps. It leaves {pct(1 - AI_SHARE)} for servers, "
    "free users, app-store fees and profit, even for a user who spends everything on the most expensive action. "
    "The raw result is rounded to a round number; where the typical cost is far below the large one (builds), "
    "the price sits between the two so typical studios are not overcharged. Deep build is priced above the rule on purpose: "
    "it is the premium option (2-3x more lessons for a longer wait), so it costs more than a Standard build.", P))
rows = [["Action", "Largest AI cost", "Rule gives", "Proposed", "AI share at typical cost", "AI share at largest cost"]]
for name, _, typ, hi, cr, _ in actions:
    raw = hi / MAX_AI_PER_CREDIT
    if cr:
        rows.append([name, usd(hi, 4), f"{raw:.0f}", f"<b>{cr}</b>",
                     pct(typ / (cr * V_MIN)), pct(hi / (cr * V_MIN))])
    else:
        rows.append([name, usd(hi, 5), f"{raw:.1f}", "<b>free</b>", "—", "—"])
A(table(rows, [2.0 * inch, 0.95 * inch, 0.95 * inch, 0.75 * inch, 1.2 * inch, 1.15 * inch]))
A(Paragraph(
    "AI share is the AI cost divided by what those credits are worth on the cheapest plan (Premium yearly). "
    "On every other plan the share is lower. Only a user who builds nothing but very large studios exceeds 30% — and still stays under 40%.", SMALL))

# 6 -------------------------------------------------------------------------
A(Paragraph("6. Proposed credit price list", H2))
rows = [["Action", "Credits", "Setting (system_settings)", "Notes"]]
for name, key, _, _, cr, note in actions:
    rows.append([name, f"<b>{cr if cr else 'free (0)'}</b>", key, note])
A(table(rows, [2.0 * inch, 0.8 * inch, 1.75 * inch, 2.45 * inch]))
A(Paragraph(
    "Prices are read by the server from <font face='Courier'>system_settings</font> once a minute — the admin team can change "
    "them at any time without a release. A user without enough credits gets a clear \"not enough credits\" message before any "
    "AI call is made, and a retried request is never charged twice. "
    "* <b>Deep build</b> needs one small change before launch: a Standard/Deep choice in the app and its own price key.", P))
A(Paragraph("What a month's allowance buys", H3))
rows = [["Plan", "Credits", "Ask AI answers", "Standard builds", "Deep builds", "A realistic month"],
        ["Free", "500", "25", "3", "2", "2 studios + 5 questions"],
        ["Pro (launch, with promo)", "2,000", "100", "13", "10", "6 studios + 55 questions"],
        ["Pro (after promo)", "1,000", "50", "6", "5", "3 studios + 27 questions"],
        ["Premium", "5,000", "250", "33", "25", "15 studios + 130 questions"]]
A(table(rows, [1.5 * inch, 0.65 * inch, 1.0 * inch, 1.05 * inch, 0.9 * inch, 1.9 * inch]))
A(Paragraph("Recall grading, flashcards, quizzes and Lightning Recall on an existing studio use no credits.", SMALL))

# 7 -------------------------------------------------------------------------
A(Paragraph("7. Plan economics: AI cost against revenue", H2))
A(Paragraph(
    f"<b>Worst case</b>: the user spends every credit on the action with the highest AI cost per credit (large Standard builds, "
    f"{usd(WORST_PER_CREDIT, 5)} per credit). <b>Typical</b>: 30% of the allowance used, mostly Ask AI "
    f"({usd(ASK_PER_CREDIT, 5)} per credit). Server cost is not included yet — see section 8.", P))
rows = [["Plan", "Billing", "Net / month", "AI worst case", "AI share", "Left (worst)", "AI typical", "Left (typical)"]]
for name, bill, _, net, cr in plans:
    w, t = cr * WORST_PER_CREDIT, cr * 0.3 * ASK_PER_CREDIT
    rows.append([name, bill, usd(net), usd(w), pct(w / net), signed(net - w), usd(t), signed(net - t)])
fw, ft = FREE_CR * WORST_PER_CREDIT, FREE_CR * 0.3 * ASK_PER_CREDIT
rows.append(["Free", "—", "$0", usd(fw), "—", signed(-fw), usd(ft), signed(-ft)])
A(table(rows, [0.75 * inch, 1.15 * inch, 0.8 * inch, 0.9 * inch, 0.65 * inch, 0.95 * inch, 0.75 * inch, 1.05 * inch]))
A(Paragraph(
    "Every paid plan is profitable on AI in the worst case. The thinnest plan is Premium yearly: about 29% if the user only asks "
    "questions, about 36% if they only build very large studios. The \"later\" prices (Pro $9.99, Premium $19.99) roughly halve the AI share.", NOTE))

# 8 -------------------------------------------------------------------------
A(Paragraph("8. Servers, free users and profit", H2))
A(Paragraph("What is left after AI must also pay for the servers and for the AI that free users consume:", P))
A(Paragraph("Profit per paying user = net revenue - AI cost - (server cost ÷ paying users) - (free users per paying user × AI cost per free user)", FORMULA))
A(Paragraph(
    "Server cost is mostly fixed (the VPS, database, storage, backups), so its share per user falls as users grow. "
    "Free users are the main risk: each one can use up to "
    f"{usd(fw)} of AI a month, and there are usually many free users for every paying one.", P))
SERVER, PAYING = 60.0, 100
A(Paragraph(f"Example: Pro monthly at launch ({usd(net_sub(4.99))} net), server <b>${SERVER:.0f}/month as a placeholder</b> "
            f"shared by {PAYING} paying users (${SERVER / PAYING:.2f} each). Replace the placeholder with the real server bill.", P))
rows = [["Free users per paying user", "Usage", "AI (paying user)", "Free users' AI", "Server share", "Profit / paying user", "Margin"]]
pro_net = net_sub(4.99)
for ratio in (5, 10, 20):
    for label, use, per in (("typical (30%, Ask)", 0.3, ASK_PER_CREDIT), ("worst (100%, large builds)", 1.0, WORST_PER_CREDIT)):
        ai = 2000 * use * per
        free = ratio * FREE_CR * use * per
        prof = pro_net - ai - free - SERVER / PAYING
        rows.append([str(ratio), label, usd(ai), usd(free), usd(SERVER / PAYING), signed(prof), pct(prof / pro_net)])
A(table(rows, [1.15 * inch, 1.6 * inch, 0.9 * inch, 0.9 * inch, 0.8 * inch, 1.05 * inch, 0.6 * inch]))
A(Paragraph(
    "With typical use the plan stays healthy even at 20 free users per paying user. Only if every user — paying and free — "
    "spends their whole allowance on large builds does the plan lose money (at 10 or more free users per paying user). "
    "That is unlikely, but the levers below protect against it.", NOTE))

A(Paragraph("Levers that raise the margin without raising prices", H3))
story += bullets([
    "<b>Move Ask AI to a cheaper model.</b> It is the most-used action and runs on Claude Sonnet 4.6, the most expensive model "
    "we use. A cheaper model could cut its cost 3-5x; at 20 credits the margin on questions would grow accordingly.",
    "<b>Give Pro's promotional 1,000 credits for the first 3 months only.</b> Permanently, it doubles Pro's worst-case AI cost.",
    "<b>Free plan: 300 credits instead of 500</b>, or keep 500 but make Deep build Pro/Premium only. "
    f"300 credits cap a free user at {usd(300 * WORST_PER_CREDIT)} of AI a month.",
    "<b>Fill the server.</b> One VPS serves every user today; server cost per user falls with every new user until it needs upgrading.",
])

# 9 -------------------------------------------------------------------------
A(Paragraph("9. App store fees", H2))
A(Paragraph(
    "If subscriptions are sold inside the iOS or Android app, Apple and Google take 15% (small-business rate, under $1M a year; "
    "30% above it) instead of Stripe's fee. Every plan stays profitable, with a higher AI share:", P))
rows = [["Plan (monthly, launch)", "Through Stripe", "Through app store (15%)", "Through app store (30%)", "AI worst case", "AI share at 30% fee"]]
for name, price, cr in (("Pro $4.99", 4.99, 2000), ("Premium $9.99", 9.99, 5000)):
    w = cr * WORST_PER_CREDIT
    rows.append([name, usd(net_sub(price)), usd(price * 0.85), usd(price * 0.70), usd(w), pct(w / (price * 0.70))])
A(table(rows, [1.4 * inch, 1.0 * inch, 1.3 * inch, 1.3 * inch, 0.95 * inch, 1.05 * inch]))
A(Paragraph("Selling through the web (Stripe) keeps the most; if in-app purchase is required, the 15% rate is the one to plan for.", SMALL))

# 10 ------------------------------------------------------------------------
A(Paragraph("10. Features not priced yet", H2))
A(Paragraph(
    "The plans list Study Studio features that are not built or not measured yet. Each needs a benchmark (run it at least "
    "10 times on real material, as the draft rightly says) before it gets a price. The same 30% rule then applies.", P))
rows = [["Feature", "Plan", "How to charge"],
        ["Notes Simplifier", "Free", "Per run, like a small build"],
        ["Teach Me / Adaptive Quiz Me", "Free (limited) / Pro", "Per AI call (each generated answer or question), like Ask AI"],
        ["Standard mock exam", "Pro", "Per exam generated"],
        ["Advanced mock exam", "Premium", "Per exam generated"],
        ["Oral exam / Scenario modes", "Premium", "Per session with a cap on AI turns, or per AI turn — a long conversation "
                                                   "under one flat price could exceed the 30% ceiling"],
        ["Deeper weakness analysis", "Premium", "Per analysis"],
        ["Heavier document processing", "Premium", "Upload limits, not credits — ingest has no per-call AI cost"]]
A(table(rows, [1.9 * inch, 1.3 * inch, 3.8 * inch]))
A(Paragraph(
    "Rule for session features: never sell an open-ended conversation for one flat price. Either charge per AI turn or "
    "cap the number of turns in a session so its largest possible cost is known.", NOTE))

# 11 ------------------------------------------------------------------------
A(Paragraph("11. Running it", H2))
story += bullets([
    "<b>Set the prices</b> in <font face='Courier'>system_settings</font> (keys in section 6). Changes apply within a minute.",
    "<b>Review monthly.</b> Every AI call is logged with its tokens and real cost (<font face='Courier'>llm_usage</font>). "
    "Once a month, compare the average real cost per action with its credit price; adjust if any action's AI share passes 30%.",
    "<b>Re-check when a model changes.</b> Model prices on OpenRouter change often, usually downwards; a model switch "
    "is the moment to re-run the benchmark.",
    "<b>Track free-user cost</b> as a separate line: AI used by free accounts per month, against the number of paying users.",
])

# 12 ------------------------------------------------------------------------
A(Paragraph("12. Assumptions", H2))
story += bullets([
    "AI costs from one benchmark run per configuration on 8 October 2026 (AI Cost Sheet). Costs vary with the material; "
    "the \"large\" figures cover the biggest build possible today.",
    f"Payment fees: Stripe {STRIPE_PCT * 100:.1f}% + ${STRIPE_FIX:.2f} per charge, plus Stripe Billing {BILLING_PCT * 100:.1f}% "
    "on subscriptions. Taxes and refunds not included.",
    "Plans, prices and allowances as in the Finance draft: Free 500 credits; Pro $4.99/month or $49.99/year, 1,000 + 1,000 "
    "promotional credits; Premium $9.99/month or $99.99/year, 5,000 credits; later prices $9.99 and $19.99 a month.",
    f"Server cost (${SERVER:.0f}/month, {PAYING} paying users) is a placeholder for illustration only.",
    "Study Studio only. OctoNotes, including transcription, is priced separately.",
])


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(MUTED)
    canvas.drawString(0.75 * inch, 0.5 * inch, f"Octopilot · Study Studio proposed pricing structure · {DATE}")
    canvas.drawRightString(letter[0] - 0.75 * inch, 0.5 * inch, f"Page {doc.page}")
    canvas.setStrokeColor(ACCENT)
    canvas.setLineWidth(2)
    canvas.line(0.75 * inch, letter[1] - 0.45 * inch, 1.6 * inch, letter[1] - 0.45 * inch)
    canvas.restoreState()


doc = SimpleDocTemplate(OUT, pagesize=letter, leftMargin=0.75 * inch, rightMargin=0.75 * inch,
                        topMargin=0.7 * inch, bottomMargin=0.75 * inch, title="Study Studio — Proposed Pricing Structure",
                        author="Octopilot")
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print(OUT)
print("V_MIN", V_MIN, "MAX_AI", MAX_AI_PER_CREDIT, "WORST", WORST_PER_CREDIT, "ASK/cr", ASK_PER_CREDIT)
