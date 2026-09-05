import json
from collections.abc import AsyncIterator

from app.model_client import ModelClient


LENGTH_WORD_COUNTS = {
    "concise": 750,
    "standard": 1250,
    "in-depth": 2200,
}


def _clean_choice(value, allowed: set[str], default: str) -> str:
    candidate = str(value or "").strip()
    if candidate.lower() in allowed:
        return candidate
    return default


def _word_count(payload: dict) -> int:
    raw = payload.get("wordCount") or payload.get("customWordCount")
    try:
        parsed = int(raw)
        if parsed > 0:
            return max(100, min(20_000, parsed))
    except (TypeError, ValueError):
        pass

    length = str(payload.get("length") or "standard").strip().lower()
    return LENGTH_WORD_COUNTS.get(length, LENGTH_WORD_COUNTS["standard"])


def _format_outline(outlines: list[dict]) -> str:
    sections = []
    for index, item in enumerate(outlines, start=1):
        outline_type = str(item.get("type") or "Body Paragraph").strip()
        title = str(item.get("title") or outline_type).strip()
        description = str(item.get("description") or "").strip()
        bullets = item.get("bullets") or []
        clean_bullets = [
            str(bullet).strip()
            for bullet in bullets
            if str(bullet).strip()
        ]

        lines = [f"Outline {index} ({outline_type}): {title}"]
        if description:
            lines.append(f"Description: {description}")
        lines.extend(f"- {bullet}" for bullet in clean_bullets)
        sections.append("\n".join(lines))

    return "\n\n".join(sections)


def _format_sources(sources: list[dict]) -> str:
    blocks = []
    for index, source in enumerate(sources, start=1):
        kind = str(source.get("kind") or "unknown").strip()
        title = str(source.get("title") or "Untitled source").strip()
        publisher = str(
            source.get("publisher") or source.get("domain") or "Unknown publisher"
        ).strip()
        author = str(source.get("author") or "Unknown author").strip()
        year = str(
            source.get("publishedYear") or source.get("year") or "n.d."
        ).strip()
        content = str(
            source.get("compactedContent")
            or source.get("content")
            or source.get("snippet")
            or source.get("text")
            or ""
        ).strip()

        blocks.append(
            "\n".join(
                [
                    f"Source {index}:",
                    f"Kind: {kind}",
                    f"Title: {title}",
                    f"Publisher: {publisher}",
                    f"Author: {author}",
                    f"Year: {year}",
                    f"Content (compacted): {content or '(No excerpt provided.)'}",
                ]
            )
        )

    return "\n\n".join(blocks)


def _format_rubric(criteria) -> str:
    if not isinstance(criteria, list):
        return "None provided"
    lines = []
    for index, criterion in enumerate(criteria, start=1):
        if not isinstance(criterion, dict):
            continue
        name = str(criterion.get("name") or f"Criterion {index}").strip()
        description = str(criterion.get("description") or "").strip()
        points = criterion.get("points")
        point_label = f" ({points} points)" if points is not None else ""
        lines.append(f"{index}. {name}{point_label}: {description}")
    return "\n".join(lines) or "None provided"


def _format_style_profile(profile) -> str:
    if not isinstance(profile, dict):
        return "None provided; use a polished academic style."
    return "\n".join(
        [
            f"Writing style: {profile.get('writing_style') or 'Not specified'}",
            (
                "Grammar preference: "
                f"{profile.get('grammar_usage_style') or 'Use correct academic grammar'}"
            ),
            (
                "Vocabulary level: "
                f"{profile.get('vocabulary_usage_style_and_level') or 'Academic'}"
            ),
            "Preserve the stated style and vocabulary while maintaining correct grammar.",
        ]
    )


def build_system_prompt(
    tone: str,
    word_count: int,
    citation_style: str,
    outline_count: int,
) -> str:
    return f"""
You are Lucas, the main academic essay generation agent for OctoPilot AI.

Write an essay of approximately {word_count} words in exactly {outline_count}
paragraphs, following the provided outlines in order. Use the {tone} writing
tone and {citation_style} citation format.

Use every supplied source where relevant. Base factual claims on the compacted
source content, distinguish source kinds appropriately, and create accurate
in-text citations. Never invent quotations, facts, authors, dates, publishers,
or source details. Include the requested keywords naturally when applicable and
satisfy every supplied rubric criterion without mentioning the rubric.

Do not add an essay title. Return strict JSON only, with no Markdown fence and
no text outside this exact shape:
{{
  "essay_content": "The full essay with in-text citations",
  "bibliography": "The fully formatted bibliography"
}}

Keep the essay itself close to {word_count} words. The bibliography is separate
and does not count toward the requested essay word count.
""".strip()


class LucasAgent:
    def __init__(self, model_client: ModelClient):
        self.model_client = model_client

    async def generate_stream(self, payload: dict) -> AsyncIterator[str]:
        organizer = payload.get("organizerState")
        if isinstance(organizer, dict):
            payload = organizer

        outlines = (
            payload.get("selectedOutlines")
            or payload.get("outlines")
            or payload.get("outline")
            or []
        )
        sources = (
            payload.get("compactedSources")
            or payload.get("sources")
            or payload.get("selectedSources")
            or []
        )

        if not isinstance(outlines, list) or not any(
            isinstance(item, dict) for item in outlines
        ):
            raise ValueError("at least one outline item is required")
        if not isinstance(sources, list) or not any(
            isinstance(item, dict) for item in sources
        ):
            raise ValueError("at least one compacted source is required")

        clean_outlines = [item for item in outlines if isinstance(item, dict)]
        clean_sources = [item for item in sources if isinstance(item, dict)]
        word_count = _word_count(payload)
        tone = _clean_choice(
            payload.get("tone"),
            {"academic", "neutral", "persuasive"},
            "Academic",
        )
        citation_style = _clean_choice(
            payload.get("citationStyle") or payload.get("citation"),
            {"apa", "mla", "chicago"},
            "APA",
        )

        system_prompt = build_system_prompt(
            tone,
            word_count,
            citation_style,
            len(clean_outlines),
        )
        assignment = {
            "analysis": payload.get("analysis") or "",
            "essayTopic": payload.get("essayTopic") or "",
            "essayType": payload.get("essayType")
            or payload.get("analyzedEssayType")
            or "",
            "scope": payload.get("scope") or "",
            "structure": payload.get("structure") or "",
            "instructions": payload.get("instructions")
            or payload.get("instructionTextInput")
            or "",
        }
        user_message = (
            "Assignment context:\n"
            f"{json.dumps(assignment, ensure_ascii=False, indent=2)}\n\n"
            f"Word Count: {word_count}\n"
            f"Writing Tone: {tone}\n"
            f"Citation Format: {citation_style}\n"
            f"Keywords: {payload.get('keywords') or 'None'}\n\n"
            "Writing-style preferences:\n"
            f"{_format_style_profile(payload.get('writingStyleProfile'))}\n\n"
            "Rubric Criteria:\n"
            f"{_format_rubric(payload.get('rubricCriteria'))}\n\n"
            f"Outlines ({len(clean_outlines)} paragraphs):\n"
            f"{_format_outline(clean_outlines)}\n\n"
            "Sources:\n"
            f"{_format_sources(clean_sources)}"
        )

        async for delta in self.model_client.stream_completion(
            system_prompt,
            user_message,
            0.4,
        ):
            if delta:
                yield delta
