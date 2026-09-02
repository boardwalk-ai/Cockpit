import json
from typing import Any

from .core import model_json


async def critique_essay(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    essay = str(context.get("essay", "")).strip()
    if not essay:
        raise ValueError("Essay is required")

    result = await model_json(
        """Critique this academic essay.
Return ONLY JSON:
{
  "score": integer,
  "issues": [
    {
      "paragraphIndex": integer,
      "type": "thesis|evidence|clarity|citations|length|structure",
      "severity": "major|minor",
      "issue": string
    }
  ],
  "ready": boolean
}""",
        json.dumps(
            {
                "essay": essay,
                "topic": context.get("essayTopic"),
                "citationStyle": context.get("draftSettings", {}).get("citationStyle"),
                "notes": args.get("notes", ""),
            }
        ),
    )

    issues = result.get("issues", [])
    context["critiqueIssues"] = issues

    return {
        "score": int(result.get("score", 0)),
        "issueCount": len(issues),
        "majorIssues": len([x for x in issues if x.get("severity") == "major"]),
        "ready": bool(result.get("ready", False)),
    }


async def revise_paragraph(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    if context.get("revisionRounds", 0) >= 8:
        return {"capped": True, "message": "Maximum revision rounds reached"}

    essay = str(context.get("essay", ""))
    paragraphs = [x.strip() for x in essay.split("\n\n") if x.strip()]

    index = int(args["paragraphIndex"])
    if index < 0 or index >= len(paragraphs):
        raise ValueError("Invalid paragraphIndex")

    result = await model_json(
        """Revise exactly one essay paragraph.
Return ONLY JSON:
{"paragraph": string}""",
        json.dumps(
            {
                "paragraph": paragraphs[index],
                "issue": args["issue"],
                "outline": (
                    context.get("outlines", [])[index]
                    if index < len(context.get("outlines", []))
                    else None
                ),
                "sources": context.get("compactedSources", [])[:5],
            }
        ),
    )

    replacement = str(result.get("paragraph", "")).strip()
    if not replacement:
        raise ValueError("Revision returned empty paragraph")

    before = paragraphs[index]
    paragraphs[index] = replacement
    context["essay"] = "\n\n".join(paragraphs)
    context["revisionRounds"] = context.get("revisionRounds", 0) + 1
    context.setdefault("revisionHistory", []).append(
        {
            "paragraphIndex": index,
            "issue": args["issue"],
            "before": before,
            "after": replacement,
        }
    )

    context["critiqueIssues"] = [
        x for x in context.get("critiqueIssues", [])
        if x.get("paragraphIndex") != index
    ]

    return {
        "paragraphIndex": index,
        "revisionRounds": context["revisionRounds"],
        "beforePreview": before[:160],
        "afterPreview": replacement[:160],
    }


async def split_paragraphs(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    content = str(context.get("humanizedContent", "")).strip()
    if not content:
        raise ValueError("humanizedContent is required")

    result = await model_json(
        """Restore paragraph boundaries in this essay.
Do not rewrite, add, remove, or reorder words.
Return ONLY JSON:
{"content": string}""",
        json.dumps(
            {
                "content": content,
                "outlines": context.get("outlines", []),
            }
        ),
    )

    value = str(result.get("content", "")).strip()
    if not value:
        raise ValueError("Paragraph splitting failed")

    context["humanizedContent"] = value
    return {"ok": True, "length": len(value)}