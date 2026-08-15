"""Generate realistic sample study materials for upload and end-to-end tests.

    python -m scripts.generate_sample_materials \\
        --count 5 --subject biology --size medium --out ./sample_materials

Writes `.txt` and `.md` notes only. Does not call the upload API.
"""

from __future__ import annotations

import argparse
import hashlib
import random
import re
import sys
from pathlib import Path

from scripts.sample_materials_catalog import SUPPORTED_SUBJECTS, TOPICS, Topic

SUPPORTED_SIZES = ("short", "medium", "long")

SIZE_PLAN = {
    "short": {
        "topic_count": 1,
        "explanation_limit": 2,
        "example_limit": 1,
        "worked_limit": 1,
        "include_pitfalls": False,
        "include_review": True,
        "min_words": 220,
    },
    "medium": {
        "topic_count": 1,
        "explanation_limit": 4,
        "example_limit": 2,
        "worked_limit": 1,
        "include_pitfalls": True,
        "include_review": True,
        "min_words": 650,
    },
    "long": {
        "topic_count": 3,
        "explanation_limit": 8,
        "example_limit": 4,
        "worked_limit": 2,
        "include_pitfalls": True,
        "include_review": True,
        "min_words": 1400,
    },
}

_TITLE_STYLES = (
    "Lecture Notes: {title}",
    "Study Guide: {title}",
    "Exam Review: {title}",
    "Concept Packet: {title}",
    "Walkthrough: {title}",
)

_INTROS = (
    "These notes are a first-pass companion for {title}. They are written to be uploaded as a study document, not as a substitute for a textbook chapter.",
    "{title} shows up on quizzes because it connects several earlier ideas. The aim here is to make those connections explicit and testable.",
    "Use this packet to review {title} before a studio upload test. Definitions come early; later sections apply them with examples.",
    "Read {title} as a structured recap: key terms, explanations, then practice. Wording is intentionally specific so retrieval tests have something to match.",
    "This set of notes treats {title} as a working toolkit. Skim the headings first, then work the examples without looking at the answers.",
)

_TRANSITIONS = (
    "The next section tightens the vocabulary so the later examples do not float free of definitions.",
    "With the overview in place, it helps to pin down the terms that exams actually use.",
    "The explanations below are ordered the way most instructors build the topic, not strictly by difficulty.",
    "Keep the definitions nearby while you read; several examples reuse them without restating every clause.",
)

_SUMMARY_OPENERS = (
    "If you remember nothing else, hold onto the following.",
    "A compact recap before you close the file:",
    "Review checklist — say each item out loud without looking back:",
    "Closing synthesis for a last-minute pass:",
)


def word_count(text: str) -> int:
    return len(text.split())


def _seed_int(subject: str, size: str, index: int) -> int:
    digest = hashlib.sha256(f"{subject}|{size}|{index}".encode()).hexdigest()
    return int(digest[:16], 16)


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "notes"


def _pick_topics(subject: str, size: str, index: int) -> list[Topic]:
    bank = TOPICS[subject]
    n = len(bank)
    plan = SIZE_PLAN[size]
    count = min(int(plan["topic_count"]), n)
    start = index % n
    # Stride through the bank so consecutive files do not share the same trio.
    stride = 3 if size == "long" else 1
    chosen: list[Topic] = []
    seen: set[str] = set()
    offset = 0
    while len(chosen) < count:
        topic = bank[(start + offset * stride) % n]
        if topic["slug"] not in seen:
            chosen.append(topic)
            seen.add(topic["slug"])
        offset += 1
        if offset > n * 2:
            break
    return chosen


def _style_index(index: int) -> int:
    return index % len(_TITLE_STYLES)


def _document_title(topics: list[Topic], index: int) -> str:
    primary = topics[0]["title"]
    styled = _TITLE_STYLES[_style_index(index)].format(title=primary)
    if len(topics) > 1:
        extras = " / ".join(t["title"] for t in topics[1:])
        return f"{styled} (with {extras})"
    return styled


def _heading(text: str, level: int, markdown: bool) -> str:
    if markdown:
        return f"{'#' * level} {text}"
    if level == 1:
        return f"{text.upper()}\n{'=' * max(len(text), 3)}"
    if level == 2:
        return f"{text.upper()}\n{'-' * max(len(text), 3)}"
    return f"{text.upper()}"


def _bold(text: str, markdown: bool) -> str:
    return f"**{text}**" if markdown else text


def _bullets(items: list[str], markdown: bool) -> list[str]:
    mark = "-" if markdown else "*"
    return [f"{mark} {item}" for item in items]


def _term_lines(terms: list[tuple[str, str]], markdown: bool) -> list[str]:
    lines: list[str] = []
    for name, definition in terms:
        if markdown:
            lines.append(f"- { _bold(name, True) }: {definition}")
        else:
            lines.append(f"* {name} — {definition}")
    return lines


def _compose_topic_sections(
    topic: Topic,
    plan: dict,
    rng: random.Random,
    markdown: bool,
    *,
    include_overview: bool,
    remaining_examples: int,
    remaining_worked: int,
    heading_level: int = 2,
) -> tuple[list[str], int, int]:
    lines: list[str] = []
    explanations = list(topic["explanations"])
    rng.shuffle(explanations)
    explanations = explanations[: int(plan["explanation_limit"])]
    h = heading_level

    if include_overview:
        lines.append(_heading("Overview", h, markdown))
        lines.append("")
        lines.append(topic["overview"])
        lines.append("")
        lines.append(rng.choice(_TRANSITIONS))
        lines.append("")

    # Vary whether terms come before or after the first explanation.
    terms_first = rng.random() < 0.55
    term_block = [_heading("Key Terms", h, markdown), ""] + _term_lines(list(topic["terms"]), markdown) + [""]

    expl_blocks: list[str] = []
    for heading, body in explanations:
        expl_blocks.extend([_heading(heading, h, markdown), "", body, ""])

    if terms_first:
        lines.extend(term_block)
        lines.extend(expl_blocks)
    else:
        lines.extend(expl_blocks)
        lines.extend(term_block)

    bullets = list(topic["bullets"])
    rng.shuffle(bullets)
    lines.append(_heading("Core Points", h, markdown))
    lines.append("")
    lines.extend(_bullets(bullets, markdown))
    lines.append("")

    examples = list(topic["examples"])
    rng.shuffle(examples)
    take_ex = min(remaining_examples, int(plan["example_limit"]), len(examples))
    if take_ex:
        lines.append(_heading("Examples", h, markdown))
        lines.append("")
        lines.extend(_bullets(examples[:take_ex], markdown))
        lines.append("")
        remaining_examples -= take_ex

    worked = list(topic["worked"])
    rng.shuffle(worked)
    take_w = min(remaining_worked, int(plan["worked_limit"]), len(worked))
    if take_w:
        for title, body in worked[:take_w]:
            lines.append(_heading(f"Worked Example: {title}", h, markdown))
            lines.append("")
            lines.append(body)
            lines.append("")
        remaining_worked -= take_w

    if plan["include_pitfalls"]:
        pitfalls = list(topic["pitfalls"])
        rng.shuffle(pitfalls)
        lines.append(_heading("Common Mistakes", h, markdown))
        lines.append("")
        lines.extend(_bullets(pitfalls, markdown))
        lines.append("")

    return lines, remaining_examples, remaining_worked


def _review_block(topics: list[Topic], rng: random.Random, markdown: bool) -> list[str]:
    questions: list[str] = []
    for topic in topics:
        pool = list(topic["review"])
        rng.shuffle(pool)
        questions.extend(pool)
    rng.shuffle(questions)
    lines = [_heading("Summary and Review", 2, markdown), "", rng.choice(_SUMMARY_OPENERS), ""]
    recap: list[str] = []
    for topic in topics:
        recap.append(f"{topic['title']}: {topic['overview'].split('.')[0]}.")
    lines.extend(_bullets(recap, markdown))
    lines.append("")
    lines.append(_heading("Check Your Understanding", 3, markdown))
    lines.append("")
    numbered = [f"{i}. {q}" for i, q in enumerate(questions, start=1)]
    lines.extend(numbered)
    lines.append("")
    return lines


def _pad_to_length(
    lines: list[str],
    topics: list[Topic],
    subject: str,
    size: str,
    rng: random.Random,
    markdown: bool,
    min_words: int,
) -> None:
    extras: list[str] = []
    for topic in topics:
        extras.append(
            f"Further note on {topic['title']}: {topic['overview']} "
            f"When this topic appears in mixed questions, start from the definitions "
            f"and only then reach for the examples."
        )
        for heading, body in topic["explanations"]:
            extras.append(f"Extension — {heading}: {body}")
        for name, definition in topic["terms"]:
            extras.append(
                f"Memory cue for {name}: {definition} "
                f"Try to reconstruct this definition before you reread it."
            )
    rng.shuffle(extras)
    idx = 0
    while word_count("\n".join(lines)) < min_words and idx < len(extras):
        if idx == 0:
            lines.append(_heading("Additional Study Notes", 2, markdown))
            lines.append("")
        lines.append(extras[idx])
        lines.append("")
        idx += 1
    # Last-resort unique filler that still stays on-subject (should rarely run).
    n = 1
    while word_count("\n".join(lines)) < min_words:
        lines.append(
            f"Extra practice prompt {n} for {subject} ({size}): "
            f"explain one idea from this packet to a peer, then write a two-sentence "
            f"correction of whatever they misunderstood. Prompt index {n} is unique "
            f"to this generated file so wording does not collapse into identical boilerplate."
        )
        lines.append("")
        n += 1


def build_document(subject: str, size: str, index: int) -> tuple[str, str, str, str]:
    """Return (filename_stem_slug, title, extension, body)."""
    rng = random.Random(_seed_int(subject, size, index))
    plan = SIZE_PLAN[size]
    topics = _pick_topics(subject, size, index)
    markdown = index % 2 == 0
    ext = "md" if markdown else "txt"
    title = _document_title(topics, index)

    lines: list[str] = [
        _heading(title, 1, markdown),
        "",
        f"Subject: {subject.title()}  ·  Length: {size}  ·  Packet {index + 1}",
        "",
        _INTROS[_style_index(index)].format(title=topics[0]["title"]),
        "",
    ]

    remaining_examples = int(plan["example_limit"]) * max(1, len(topics))
    remaining_worked = int(plan["worked_limit"]) * max(1, len(topics))
    for i, topic in enumerate(topics):
        if len(topics) > 1:
            part = f"Part {i + 1}: {topic['title']}"
            lines.append(_heading(part, 2, markdown))
            lines.append("")
        section, remaining_examples, remaining_worked = _compose_topic_sections(
            topic,
            plan,
            rng,
            markdown,
            include_overview=True,
            remaining_examples=remaining_examples,
            remaining_worked=remaining_worked,
            heading_level=3 if len(topics) > 1 else 2,
        )
        lines.extend(section)

    if plan["include_review"]:
        lines.extend(_review_block(topics, rng, markdown))

    _pad_to_length(lines, topics, subject, size, rng, markdown, int(plan["min_words"]))

    body = "\n".join(lines).rstrip() + "\n"
    slug = _slugify(topics[0]["slug"])
    if len(topics) > 1:
        slug = _slugify(f"{topics[0]['slug']}-{topics[1]['slug']}")
    return slug, title, ext, body


def unique_filename(out_dir: Path, subject: str, slug: str, size: str, index: int, ext: str) -> Path:
    stem = f"{subject}-{slug}-{size}-{index + 1:02d}"
    candidate = out_dir / f"{stem}.{ext}"
    extra = 2
    while candidate.exists():
        candidate = out_dir / f"{stem}-{extra}.{ext}"
        extra += 1
    return candidate


def generate_files(count: int, subject: str, size: str, out: str | Path) -> list[Path]:
    subject = subject.strip().lower()
    size = size.strip().lower()
    if subject not in SUPPORTED_SUBJECTS:
        raise ValueError(
            f"unsupported subject {subject!r}. Choose one of: {', '.join(SUPPORTED_SUBJECTS)}"
        )
    if size not in SUPPORTED_SIZES:
        raise ValueError(
            f"unsupported size {size!r}. Choose one of: {', '.join(SUPPORTED_SIZES)}"
        )
    if count < 1:
        raise ValueError("count must be a positive integer")

    out_dir = Path(out)
    out_dir.mkdir(parents=True, exist_ok=True)

    written: list[Path] = []
    used: set[str] = set()
    for index in range(count):
        slug, _title, ext, body = build_document(subject, size, index)
        path = unique_filename(out_dir, subject, slug, size, index, ext)
        extra = 2
        while path.name in used:
            path = unique_filename(out_dir, subject, f"{slug}-{extra}", size, index, ext)
            extra += 1
        used.add(path.name)
        path.write_text(body, encoding="utf-8")
        written.append(path)
    return written


def _positive_count(value: str) -> int:
    try:
        count = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"count must be an integer, got {value!r}") from exc
    if count < 1:
        raise argparse.ArgumentTypeError("count must be a positive integer")
    return count


def _choice(name: str, allowed: tuple[str, ...]):
    def parser(value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in allowed:
            raise argparse.ArgumentTypeError(
                f"unsupported {name} {value!r}. Choose one of: {', '.join(allowed)}"
            )
        return normalized

    return parser


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m scripts.generate_sample_materials",
        description="Generate realistic sample study notes (.txt / .md) for upload testing.",
    )
    parser.add_argument(
        "--count",
        type=_positive_count,
        required=True,
        help="Exact number of files to write.",
    )
    parser.add_argument(
        "--subject",
        type=_choice("subject", SUPPORTED_SUBJECTS),
        required=True,
        help=f"Subject to generate. One of: {', '.join(SUPPORTED_SUBJECTS)}.",
    )
    parser.add_argument(
        "--size",
        type=_choice("size", SUPPORTED_SIZES),
        required=True,
        help=f"Approximate document length. One of: {', '.join(SUPPORTED_SIZES)}.",
    )
    parser.add_argument(
        "--out",
        required=True,
        help="Output folder (created if it does not exist).",
    )
    return parser


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    return build_parser().parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    paths = generate_files(args.count, args.subject, args.size, args.out)
    out = Path(args.out).resolve()
    print(f"Wrote {len(paths)} {args.subject} ({args.size}) file(s) to {out}")
    for path in paths:
        print(f"  {path.name}  ({word_count(path.read_text(encoding='utf-8'))} words)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
