"""Builds docs/pricing/study-studio-cost-sheet.pdf from the benchmark results
in docs/pricing/data (bench.py output) and the OpenRouter price snapshot.

    python docs/pricing/make_cost_sheet.py
"""
import json
import math
import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table,
                                TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
OUT = os.path.join(HERE, "study-studio-cost-sheet.pdf")

runs = {k: json.load(open(os.path.join(DATA, f"{k}.json"), encoding="utf-8"))
        for k in ["b1-flashlite", "b1-glm", "b2-flashlite", "b2-glm"]}
prices = json.load(open(os.path.join(DATA, "openrouter_prices_2026-10-08.json"), encoding="utf-8"))
prices["anthropic/claude-sonnet-4-6"] = {"name": "Anthropic: Claude Sonnet 4.6", "in": 3.0, "out": 15.0, "cache": 0.3,
                                         "max_out": 64000, "ctx": 1000000, "reasoning": True}

FL, GLM, SON = "google/gemini-3.1-flash-lite-preview", "z-ai/glm-5.3-flash", "anthropic/claude-sonnet-4-6"

# ---------------------------------------------------------------- styles ---
ss = getSampleStyleSheet()
INK, MUTED, ACCENT, LINE, SOFT = (colors.HexColor(h) for h in ("#1b1a19", "#6b6660", "#C4122A", "#d9d4cc", "#f5f2ec"))
H1 = ParagraphStyle("H1", parent=ss["Title"], fontName="Helvetica-Bold", fontSize=22, leading=26, textColor=INK, alignment=TA_LEFT, spaceAfter=4)
H2 = ParagraphStyle("H2", parent=ss["Heading2"], fontName="Helvetica-Bold", fontSize=13.5, leading=17, textColor=INK, spaceBefore=14, spaceAfter=6)
H3 = ParagraphStyle("H3", parent=ss["Heading3"], fontName="Helvetica-Bold", fontSize=10.5, leading=13, textColor=INK, spaceBefore=8, spaceAfter=3)
P = ParagraphStyle("P", parent=ss["BodyText"], fontName="Helvetica", fontSize=9.2, leading=12.6, textColor=INK, spaceAfter=5)
SMALL = ParagraphStyle("S", parent=P, fontSize=7.8, leading=10, textColor=MUTED)
CELL = ParagraphStyle("C", parent=P, fontSize=8, leading=10, spaceAfter=0)
CELLB = ParagraphStyle("CB", parent=CELL, fontName="Helvetica-Bold")
NOTE = ParagraphStyle("N", parent=P, backColor=SOFT, borderPadding=(6, 7, 6, 7), leftIndent=7, rightIndent=7, spaceBefore=4, spaceAfter=9)


def c(x, bold=False):
    return Paragraph(str(x), CELLB if bold else CELL)


def table(rows, widths, header=True, zebra=True, bold_last=False):
    data = [[c(v, bold=(header and i == 0) or (bold_last and i == len(rows) - 1)) for v in r] for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1 if header else 0)
    st = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, 0), 0.8, INK),
          ("LINEBELOW", (0, 1), (-1, -1), 0.25, LINE), ("TOPPADDING", (0, 0), (-1, -1), 3.5),
          ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5), ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4)]
    if zebra:
        for i in range(2, len(rows), 2):
            st.append(("BACKGROUND", (0, i), (-1, i), SOFT))
    t.setStyle(TableStyle(st))
    return t


def usd(x, d=4):
    return f"${x:,.{d}f}"


def mt(m):  # model short name
    return {FL: "Gemini 3.1 Flash Lite", GLM: "GLM 5.3 Flash", SON: "Claude Sonnet 4.6"}.get(m, prices.get(m, {}).get("name", m).split(": ")[-1])


def cost(model, tin, tout):
    p = prices[model]
    return tin * p["in"] / 1e6 + tout * p["out"] / 1e6


# --------------------------------------------------------- derived data ---
def build_parts(r):
    bf = r["build"]["usage"]["byFeature"]
    les = bf["build_lesson"]
    fixed = {k: v for k, v in bf.items() if k != "build_lesson"}
    return les, fixed


summary = {}
for k, r in runs.items():
    b, u = r["build"], r["build"]["usage"]
    les, fixed = build_parts(r)
    summary[k] = dict(
        chars=sum(f["chars"] for f in r["files"]), lessons=b["lessons"], cards=b["cards"], quiz=b["quiz"],
        scen=b["scenarios"], secs=b["seconds"], cost=u["costUsd"], pin=u["promptTokens"], pout=u["completionTokens"],
        think=u["reasoningTokens"], calls=u["calls"], per_lesson=les["costUsd"] / les["calls"],
        lesson_in=les["promptTokens"] / les["calls"], lesson_out=les["completionTokens"] / les["calls"],
        fixed=sum(v["costUsd"] for v in fixed.values()), fixed_in=sum(v["promptTokens"] for v in fixed.values()),
        fixed_out=sum(v["completionTokens"] for v in fixed.values()), lesson_chars=b["lessonChars"],
    )

ask_calls = [r["steps"]["ask"] for r in runs.values()]
ask_avg = sum(a["costUsd"] for a in ask_calls) / sum(a["calls"] for a in ask_calls)
ask_in = sum(a["promptTokens"] for a in ask_calls) / sum(a["calls"] for a in ask_calls)
ask_out = sum(a["completionTokens"] for a in ask_calls) / sum(a["calls"] for a in ask_calls)
gr = [r["steps"]["grade"] for r in runs.values()]
grade_in = sum(g["promptTokens"] for g in gr) / sum(g["calls"] for g in gr)
grade_out = sum(g["completionTokens"] for g in gr) / sum(g["calls"] for g in gr)

# Credit economics: packs sold through Stripe (2.9% + $0.30 per payment).
packs = [(50, 0.99), (300, 4.99), (500, 7.99), (1000, 9.99), (2500, 19.99), (5000, 39.99)]
pack_rows = []
for n, p in packs:
    net = p - (p * 0.029 + 0.30)
    pack_rows.append((n, p, p / n, net / n))
worst_net = min(r[3] for r in pack_rows)  # the cheapest credits we sell

# ------------------------------------------------------------- document ---
story = []
story.append(Paragraph("Study Studio — AI Cost Sheet", H1))
story.append(Paragraph("Benchmark of the production build pipeline · 8 October 2026 · prices from OpenRouter on the same day", SMALL))
story.append(Spacer(1, 8))

story.append(Paragraph("1. Summary", H2))
fl1, gl1, fl2, gl2 = (summary[k] for k in ["b1-flashlite", "b1-glm", "b2-flashlite", "b2-glm"])
story.append(Paragraph(
    f"We built two real studios in the production app — a single 9-page PDF reading, and a mixed set of two textbook "
    f"chapters, a photographed page and a slide deck — once with each build model. Every number below is the cost "
    f"OpenRouter reported for each call, with model “thinking” turned off.", P))
story.append(table([
    ["", "Standard build<br/>Gemini 3.1 Flash Lite", "Deep build<br/>GLM 5.3 Flash"],
    ["Single PDF (9 pages, 31k chars)", f"{usd(fl1['cost'])} · {fl1['lessons']} lessons · {fl1['secs']:.0f} s",
     f"{usd(gl1['cost'])} · {gl1['lessons']} lessons · {gl1['secs'] / 60:.1f} min"],
    ["2 PDFs + image + PPTX (63 pages, 186k chars)", f"{usd(fl2['cost'])} · {fl2['lessons']} lessons · {fl2['secs']:.0f} s",
     f"{usd(gl2['cost'])} · {gl2['lessons']} lessons · {gl2['secs'] / 60:.1f} min"],
    ["Cost per lesson", f"{usd(fl1['per_lesson'])} – {usd(fl2['per_lesson'])}", f"{usd(gl1['per_lesson'])} – {usd(gl2['per_lesson'])}"],
    ["Lesson depth (avg. explanation length)", f"{fl1['lesson_chars'] // fl1['lessons']:,} – {fl2['lesson_chars'] // fl2['lessons']:,} chars",
     f"{gl1['lesson_chars'] // gl1['lessons']:,} – {gl2['lesson_chars'] // gl2['lessons']:,} chars"],
], [2.3 * inch, 2.2 * inch, 2.2 * inch]))
story.append(Spacer(1, 6))
story.append(Paragraph(
    f"<b>Key points.</b> A studio build costs about <b>3–5 cents</b> with either model. Ask AI costs about "
    f"<b>{usd(ask_avg, 3)}</b> an answer, and grading a spoken recall answer costs a hundredth of a cent. Uploading "
    f"and reading files (text extraction, OCR, search index) uses no paid AI. GLM 5.3 Flash writes "
    f"<b>2–3× more lessons</b>, each <b>2–3× longer</b>, for a similar total cost, but a build takes "
    f"<b>6–7 minutes</b> instead of about 20 seconds — so we offer it as a <b>Deep build</b> (better studio, longer wait) "
    f"next to the fast <b>Standard build</b>.", NOTE))

story.append(Paragraph("2. How it was measured", H2))
story.append(Paragraph(
    "• <b>Real pipeline:</b> the production Rust service (study-api) on the production server, with its own "
    "upload, ingest and build workers, run against throwaway copies of the production databases (no user data changed).<br/>"
    "• <b>One run per configuration</b> (2 materials × 2 build models). AI output length varies between runs; "
    "expect roughly ±20–30%.<br/>"
    "• <b>Thinking off</b> on every call. GLM 5.3 Flash cannot turn thinking off (OpenRouter returns "
    "“Reasoning is mandatory”), so it runs with <i>effort: minimal</i>: 16–159 thinking tokens per whole build.<br/>"
    "• <b>Costs</b> are OpenRouter's own <i>usage.cost</i> per call, stored per call in <i>llm_usage</i> "
    "(tokens in/out, thinking tokens, cost, latency, build id).<br/>"
    "• After each build: 3 Ask AI questions and 3 spoken-recall gradings on the new studio.", P))

story.append(Paragraph("3. Test material", H2))
rows = [["Run", "File", "Type", "Size", "Pages", "Text read", "Chunks", "Ingest"]]
pages = {"EBSCO-FullText-09_08_2026.pdf": "9", "marketing-ch1.pdf": "27", "marketing-ch2.pdf": "36",
         "marketing-ch3-page.jpg": "1 photo", "marketing-ch3-slides.pptx": "5 slides"}
kinds = {"pdf": "PDF (text)", "jpg": "Image (OCR)", "pptx": "PowerPoint"}
for k, label in [("b1-flashlite", "Build 1"), ("b2-glm", "Build 2")]:
    for f in runs[k]["files"]:
        rows.append([label, f["file"], kinds[f["file"].rsplit(".", 1)[1]], f"{f['bytes'] / 1e6:.2f} MB", pages[f["file"]],
                     f"{f['chars']:,} chars", f["passages"], f"{f['seconds']:.0f} s"])
story.append(table(rows, [0.55 * inch, 1.8 * inch, 0.8 * inch, 0.6 * inch, 0.6 * inch, 0.85 * inch, 0.55 * inch, 0.55 * inch]))
story.append(Paragraph(
    "Build 1 is a 9-page journal reading. Build 2 is OpenStax <i>Principles of Marketing</i> (CC BY): chapter 1 and "
    "chapter 2 as PDFs, a photo of the first page of chapter 3 (JPG, read by OCR), and a 5-slide deck on chapter 3. "
    "Ingest — text extraction, OCR (self-hosted Hirara), splitting into passages and embedding (self-hosted bge-m3) — "
    "costs no AI money. In the Flash Lite run of Build 2 the photo's OCR came back empty while the server was busy "
    "(fixed since: OCR now retries); it read correctly in the GLM run.", SMALL))

story.append(Paragraph("4. Models and prices (OpenRouter, USD per 1M tokens)", H2))
rows = [["Model", "Used for", "Input", "Output", "Cached input", "Max output", "Thinking"]]
used = {FL: "Standard build, grading", GLM: "Deep build (tested)", SON: "Ask AI, concept maps"}
for m in [FL, GLM, SON]:
    p = prices[m]
    rows.append([f"{mt(m)}<br/><font size=6.5 color='#6b6660'>{m}</font>", used[m], usd(p["in"], 3), usd(p["out"], 2),
                 usd(p["cache"], 3), f"{p['max_out']:,}", "can't turn off" if m == GLM else "off"])
story.append(table(rows, [1.95 * inch, 1.35 * inch, 0.6 * inch, 0.6 * inch, 0.75 * inch, 0.75 * inch, 0.75 * inch]))

story.append(Paragraph("5. Build results", H2))
rows = [["", "B1 · Flash Lite", "B1 · GLM", "B2 · Flash Lite", "B2 · GLM"]]
keys = ["b1-flashlite", "b1-glm", "b2-flashlite", "b2-glm"]
S_ = [summary[k] for k in keys]
rows += [
    ["Material read", *[f"{s['chars']:,} chars" for s in S_]],
    ["Lessons", *[s["lessons"] for s in S_]],
    ["Flashcards / quiz questions", *[f"{s['cards']} / {s['quiz']}" for s in S_]],
    ["Scenarios", *[s["scen"] for s in S_]],
    ["Lesson text written", *[f"{s['lesson_chars']:,} chars" for s in S_]],
    ["AI calls", *[s["calls"] for s in S_]],
    ["Tokens in / out", *[f"{s['pin']:,} / {s['pout']:,}" for s in S_]],
    ["Thinking tokens", *[s["think"] for s in S_]],
    ["Build time", *[f"{s['secs']:.0f} s" if s["secs"] < 120 else f"{s['secs'] / 60:.1f} min" for s in S_]],
    ["<b>Build cost</b>", *[f"<b>{usd(s['cost'])}</b>" for s in S_]],
]
story.append(table(rows, [1.9 * inch, 1.2 * inch, 1.2 * inch, 1.2 * inch, 1.2 * inch]))
story.append(Spacer(1, 4))
story.append(Paragraph(
    "Build 2 with Flash Lite returned no scenarios: the model's reply couldn't be parsed (now logged for diagnosis). "
    "Its cost still includes that call.", SMALL))

story.append(Paragraph("Cost by call type", H3))
rows = [["Call", "What it reads", "Runs per build", *["B1 · FL", "B1 · GLM", "B2 · FL", "B2 · GLM"]]]
what = {"build_outline": ("Plan the lessons", "All material, up to 120,000 chars", "1"),
        "build_lesson": ("Write one lesson", "8 most relevant passages", "1 per lesson"),
        "build_scenarios": ("Application scenarios", "All material, up to 120,000 chars", "1")}
for f, (name, reads, n) in what.items():
    cells = []
    for k in keys:
        v = runs[k]["build"]["usage"]["byFeature"][f]
        cells.append(f"{usd(v['costUsd'])}<br/><font size=6.5 color='#6b6660'>{v['calls']}× · {v['promptTokens']:,} in / {v['completionTokens']:,} out</font>")
    rows.append([name, reads, n, *cells])
story.append(table(rows, [1.15 * inch, 1.45 * inch, 0.75 * inch, 0.95 * inch, 0.95 * inch, 0.95 * inch, 0.95 * inch]))
story.append(Spacer(1, 4))
story.append(Paragraph(
    "Lessons (each also gets its flashcards, quiz and concept map in the same call) are <b>62–88%</b> of a build's cost. "
    "The outline and scenario calls read the material itself, so they grow with its size until the 120,000-character cap.", SMALL))

story.append(Paragraph("6. Other features", H2))
rows = [["Feature", "Model", "Tokens per call (in / out)", "Cost per call", "Notes"],
        ["Ask AI (one answer)", mt(SON), f"{ask_in:,.0f} / {ask_out:,.0f}", usd(ask_avg), "12 answers measured, $0.0087–0.0097"],
        ["Spoken recall grading", "Build model", f"{grade_in:,.0f} / {grade_out:,.0f}", "$0.00004 – 0.00007", "Only when the word check fails"],
        ["Concept map (older studios)", mt(SON), "—", "≈ $0.017*", "New builds include maps at no extra call"],
        ["Topic connections (older studios)", mt(SON), "—", "small*", "New builds include them"],
        ["Upload / ingest / search", "self-hosted", "—", "$0 AI", "Server CPU only"],
        ["Copy a shared studio", "—", "—", "$0 AI", "Vectors are copied"]]
story.append(table(rows, [1.6 * inch, 1.15 * inch, 1.3 * inch, 1.0 * inch, 1.85 * inch]))
story.append(Paragraph("* measured on 7 Oct 2026 (connections + one concept map = $0.017 together).", SMALL))

story.append(Paragraph("7. Cost model — how to estimate any build", H2))
story.append(Paragraph(
    "<b>build cost ≈ outline(material) + scenarios(material) + lessons × cost per lesson</b>", P))
story.append(Paragraph(
    "• <b>outline + scenarios</b> read the whole material (≈ 4 characters per token), capped at 120,000 characters "
    "(≈ 25,000 tokens) each.<br/>"
    "• <b>lessons</b> — the model decides how many from the material: a short note 2–3, a chapter 6–12, a long "
    "book 20+. GLM splits finer (2–3× as many as Flash Lite on the same material).<br/>"
    "• <b>cost per lesson</b> is steady across materials (each lesson reads ~8 passages).", P))
fl_fixed_max = cost(FL, 2 * 25000, fl2["fixed_out"])
gl_fixed_max = cost(GLM, 2 * 25000, gl2["fixed_out"])
story.append(table([
    ["Constant", "Standard (Flash Lite)", "Deep (GLM 5.3 Flash)"],
    ["Outline + scenarios, small material (31k chars)", usd(fl1["fixed"]), usd(gl1["fixed"])],
    ["Outline + scenarios, at the 120k cap", f"{usd(fl2['fixed'])} measured · ≤ {usd(fl_fixed_max)}", f"{usd(gl2['fixed'])} measured · ≤ {usd(gl_fixed_max)}"],
    ["Cost per lesson", f"{usd(fl1['per_lesson'])} – {usd(fl2['per_lesson'])}", f"{usd(gl1['per_lesson'])} – {usd(gl2['per_lesson'])}"],
    ["Tokens per lesson (in / out)", f"{fl1['lesson_in']:,.0f} / {fl1['lesson_out']:,.0f}", f"{gl1['lesson_in']:,.0f} / {gl1['lesson_out']:,.0f}"],
], [2.6 * inch, 2.1 * inch, 2.1 * inch]))

story.append(Paragraph("Estimated builds by size", H3))
sizes = [("Short note (1–3 pages, ~6k chars)", 6000, 3, 6), ("Reading (9 pages, ~31k chars)", 31000, 7, 19),
         ("Chapter (~40 pages, ~110k chars)", 110000, 11, 24), ("Several chapters (≥120k chars, capped)", 120000, 15, 30),
         ("Whole book (cap reached, many topics)", 120000, 25, 40)]
rows = [["Material", "Standard lessons", "Standard cost", "Deep lessons", "Deep cost"]]
for name, chars, ln_fl, ln_gl in sizes:
    toks = min(chars, 120000) / 4
    f_fixed = cost(FL, 2 * toks, fl1["fixed_out"] if chars < 60000 else fl2["fixed_out"])
    g_fixed = cost(GLM, 2 * toks, gl1["fixed_out"] if chars < 60000 else gl2["fixed_out"])
    rows.append([name, ln_fl, usd(f_fixed + ln_fl * fl2["per_lesson"], 3), ln_gl, usd(g_fixed + ln_gl * gl2["per_lesson"], 3)])
story.append(table(rows, [2.5 * inch, 1.0 * inch, 1.1 * inch, 1.0 * inch, 1.1 * inch]))
story.append(Paragraph(
    "Row 2 matches Build 1 and row 4 is close to Build 2 (measured); the lesson counts in the other rows are estimates. Today the outline reads "
    "only the first 120,000 characters, so very large uploads get lessons for their first ~40–50 pages only — raising "
    "the cap would add about $0.01–0.02 per large build plus the extra lessons.", SMALL))

story.append(Paragraph("8. One build with other models (projected)", H2))
story.append(Paragraph(
    "Measured token counts × each model's price. The Standard rows use Flash Lite's tokens (fewer, shorter lessons); "
    "the Deep rows use GLM's tokens (more, longer lessons). A different model will write a different amount, and "
    "quality and speed are untested — these are price comparisons, not recommendations.", P))
cands = [FL, GLM, "anthropic/claude-haiku-5.5", "openai/gpt-6-luna", "qwen/qwen3.8-flash", "xiaomi/mimo-v2.6-flash",
         "google/gemini-2.5-flash-lite", "deepseek/deepseek-v4-pro", "openai/gpt-oss-120b", "qwen/qwen3.7-flash", "google/gemini-3.8-flash"]
rows = [["Model", "In / out per 1M", "Standard-size build<br/>B1 · B2", "Deep-size build<br/>B1 · B2", "Ask AI answer"]]
for m in cands:
    p = prices[m]
    std = [cost(m, summary[k]["pin"], summary[k]["pout"]) for k in ("b1-flashlite", "b2-flashlite")]
    deep = [cost(m, summary[k]["pin"], summary[k]["pout"]) for k in ("b1-glm", "b2-glm")]
    tag = {FL: " (Standard measured)", GLM: " (Deep measured)"}.get(m, "")
    rows.append([f"{mt(m)}{tag}<br/><font size=6.5 color='#6b6660'>{m}</font>", f"{usd(p['in'], 3)} / {usd(p['out'], 2)}",
                 f"{usd(std[0], 4)} · {usd(std[1], 4)}", f"{usd(deep[0], 4)} · {usd(deep[1], 4)}", usd(cost(m, ask_in, ask_out), 5)])
rows.append([f"{mt(SON)} (Ask AI today)<br/><font size=6.5 color='#6b6660'>{SON}</font>", "$3.000 / $15.00",
             f"{usd(cost(SON, fl1['pin'], fl1['pout']), 3)} · {usd(cost(SON, fl2['pin'], fl2['pout']), 3)}",
             f"{usd(cost(SON, gl1['pin'], gl1['pout']), 3)} · {usd(cost(SON, gl2['pin'], gl2['pout']), 3)}", usd(ask_avg, 5) + " (measured)"])
story.append(table(rows, [2.35 * inch, 1.1 * inch, 1.2 * inch, 1.2 * inch, 0.95 * inch]))
story.append(Paragraph("Measured: Flash Lite's Standard columns and GLM's Deep columns (OpenRouter's billed cost) and Sonnet's Ask AI. Every other cell is a projection that ignores cache discounts and retries.", SMALL))

story.append(Paragraph("9. Credit economics", H2))
story.append(Paragraph("OctoCredit packs sold through Stripe (fee assumed 2.9% + $0.30 per payment).", P))
rows = [["Pack", "Price", "Price per credit", "Net per credit after Stripe"]]
for n, p, per, net in pack_rows:
    rows.append([f"{n:,} credits", usd(p, 2), usd(per, 4), usd(net, 4)])
story.append(table(rows, [1.6 * inch, 1.2 * inch, 1.6 * inch, 2.0 * inch]))
story.append(Paragraph(
    f"The cheapest credit we sell nets <b>{usd(worst_net, 4)}</b> (the 5,000 pack). Margins below use that worst case; "
    f"smaller packs earn more per credit.", SMALL))

story.append(Paragraph("Suggested prices", H3))
std_typ = (fl1["cost"] + fl2["cost"]) / 2
deep_typ = (gl1["cost"] + gl2["cost"]) / 2
std_worst = cost(FL, 2 * 30000, fl2["fixed_out"]) + 25 * fl2["per_lesson"]
deep_worst = cost(GLM, 2 * 30000, gl2["fixed_out"]) + 40 * gl2["per_lesson"]
sugg = [("Standard build (Flash Lite, ~20 s)", 25, std_typ, std_worst),
        ("Deep build (GLM 5.3 Flash, 6–7 min)", 40, deep_typ, deep_worst),
        ("Ask AI answer", 5, ask_avg, 0.0125),
        ("Concept map (older studios)", 10, 0.017, 0.025),
        ("Spoken recall grading", 0, 0.00006, 0.0001)]
rows = [["Action", "Credits", "AI cost typical / high", "Revenue at worst-case credit", "Margin typical / high"]]
for name, cr, typ, hi in sugg:
    rev = cr * worst_net
    m = (f"{rev / typ:.1f}× / {rev / hi:.1f}×" if cr else "free")
    rows.append([name, cr if cr else "0 (free)", f"{usd(typ, 4)} / {usd(hi, 4)}", usd(rev, 3) if cr else "—", m])
story.append(table(rows, [2.2 * inch, 0.65 * inch, 1.45 * inch, 1.3 * inch, 1.2 * inch]))
story.append(Paragraph(
    "“High” = a large upload at the cap with many lessons (25 Standard / 40 Deep). With the 1,000-credit pack "
    f"(net {usd(pack_rows[3][3], 4)} a credit) every margin is about 25% higher than shown.", SMALL))

story.append(Paragraph("How to set them", H3))
story.append(Paragraph(
    "Prices live in the octopilot database's <i>system_settings</i> and apply within a minute, no deploy:<br/>"
    "• fixed per action: <i>study_price_build</i>, <i>study_price_ask</i>, <i>study_price_concepts</i>, "
    "<i>study_price_connections</i>, <i>study_price_grade</i> (0 = free);<br/>"
    "• or metered: <i>study_credits_per_usd</i> — real OpenRouter cost × rate, rounded up, at least 1 credit "
    "(e.g. 500 ⇒ Standard build ≈ 14–22, Ask AI ≈ 5).<br/>"
    "A user short of credits gets “not enough OctoCredits” before any AI call; builds are charged only when they "
    "succeed. A Deep build option needs a small app change (a build-mode choice → the GLM model) before it can be sold.", P))

story.append(Paragraph("10. Caveats", H2))
story.append(Paragraph(
    "• One run per configuration; lesson counts and lengths vary between runs (±20–30% expected).<br/>"
    "• Two materials only (a reading and a textbook set). Very large uploads hit the 120k-character outline cap.<br/>"
    "• Model prices are a snapshot of 8 Oct 2026; Claude Haiku 5.5 and GPT-6 Luna were days old and may change.<br/>"
    "• GLM's thinking can't be switched off; at minimal effort it used 16–159 thinking tokens a build (negligible).<br/>"
    "• Ask AI uses Claude Sonnet 4.6 — by far the most expensive per call; moving it to a cheaper model is the "
    "largest saving available (see section 8), quality to be checked first.<br/>"
    "• Re-check monthly from <i>llm_usage</i> (every call: model, tokens, thinking tokens, cost, latency, feature, build).", P))

story.append(PageBreak())
story.append(Paragraph("Appendix — lessons produced", H2))
for k, label in [("b1-flashlite", "Build 1 · Flash Lite"), ("b1-glm", "Build 1 · GLM 5.3 Flash"),
                 ("b2-flashlite", "Build 2 · Flash Lite"), ("b2-glm", "Build 2 · GLM 5.3 Flash")]:
    t = runs[k]["build"]["titles"]
    story.append(KeepTogether([Paragraph(f"{label} ({len(t)})", H3), Paragraph(" · ".join(t), SMALL)]))


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(MUTED)
    canvas.drawString(0.75 * inch, 0.5 * inch, "Octopilot · Study Studio AI cost sheet · 2026-10-08")
    canvas.drawRightString(letter[0] - 0.75 * inch, 0.5 * inch, f"Page {doc.page}")
    canvas.setStrokeColor(ACCENT)
    canvas.setLineWidth(2)
    canvas.line(0.75 * inch, letter[1] - 0.45 * inch, 1.6 * inch, letter[1] - 0.45 * inch)
    canvas.restoreState()


doc = SimpleDocTemplate(OUT, pagesize=letter, leftMargin=0.75 * inch, rightMargin=0.75 * inch,
                        topMargin=0.7 * inch, bottomMargin=0.75 * inch, title="Study Studio — AI Cost Sheet",
                        author="Octopilot")
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print(OUT)
