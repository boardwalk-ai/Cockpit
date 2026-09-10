from typing import Any

from .core import (
    evaluate_sources,
    generate_outlines,
    plan_essay,
    write_essay,
)
from .humanizer import humanize_essay
from .research import (
    compact_sources,
    scrape_sources,
    search_sources,
)
from .revision import (
    critique_essay,
    revise_paragraph,
    split_paragraphs,
)


async def execute_tool(
    name: str,
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:

    if name == "echo":
        return args

    if name == "plan_essay":
        return await plan_essay(args, context)

    if name == "generate_outlines":
        return await generate_outlines(args, context)

    if name == "search_sources":
        return await search_sources(args, context)

    if name == "scrape_sources":
        return await scrape_sources(args, context)

    if name == "compact_sources":
        return await compact_sources(args, context)

    if name == "evaluate_sources":
        return await evaluate_sources(args, context)

    if name == "write_essay":
        return await write_essay(args, context)

    if name == "critique_essay":
        return await critique_essay(args, context)

    if name == "revise_paragraph":
        return await revise_paragraph(args, context)

    if name == "humanize_essay":
        return await humanize_essay(args, context)

    if name == "split_paragraphs":
        return await split_paragraphs(args, context)

    if name == "ask_user":
        return {
            "pause": True,
            "field": args.get("field", ""),
            "question": args.get("question", ""),
            "options": args.get("options", []),
            "suggestions": args.get("suggestions", []),
            "inputType": args.get("inputType", "text"),
            "allowCustom": args.get("allowCustom", False),
        }

    if name == "finalize_export":
        context["formatAnswers"] = {
            **context.get("formatAnswers", {}),
            **{
                key: value
                for key, value in args.items()
                if isinstance(value, str) and value.strip()
            },
        }

        context["exportReady"] = True

        return {
            "title": (
                context["formatAnswers"].get("finalEssayTitle")
                or context.get("essayTopic")
                or "Ghostwriter Draft"
            ),
            "pageCount": 1,
            "nextRecommendedAction": "ask_user(humanizerChoice)",
        }

    if name == "finalize_export_humanized":
        if not context.get("humanizedContent"):
            raise ValueError("humanizedContent is required")

        context["exportReady"] = True

        return {
            "title": (
                context.get("formatAnswers", {}).get("finalEssayTitle")
                or context.get("essayTopic")
                or "Ghostwriter Draft"
            ),
            "pageCount": 1,
        }

    raise ValueError(f"Tool implementation not registered: {name}")