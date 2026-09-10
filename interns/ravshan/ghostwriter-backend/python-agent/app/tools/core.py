import json
import os
from typing import Any

import httpx


OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"


async def model_json(
    system: str,
    user: str,
    *,
    temperature: float = 0.3,
) -> Any:
    api_key = os.getenv("OPENROUTER_API_KEY")
    model = os.getenv(
        "GHOSTWRITER_ORCHESTRATOR_MODEL",
        os.getenv("OPENROUTER_MODEL", ""),
    )

    if not api_key or not model:
        raise RuntimeError("OpenRouter configuration missing")

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": temperature,
        "response_format": {"type": "json_object"},
    }

    async with httpx.AsyncClient(timeout=90) as client:
        response = await client.post(
            OPENROUTER_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": "https://octopilotai.com",
                "X-Title": "OctoPilot AI",
            },
            json=payload,
        )

    response.raise_for_status()

    content = response.json()["choices"][0]["message"]["content"]
    return parse_json_loose(content)


def parse_json_loose(content: str) -> Any:
    text = content.strip()

    if text.startswith("```"):
        text = text.replace("```json", "", 1)
        text = text.replace("```", "").strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    obj_start = text.find("{")
    obj_end = text.rfind("}")

    if obj_start >= 0 and obj_end > obj_start:
        try:
            return json.loads(text[obj_start : obj_end + 1])
        except json.JSONDecodeError:
            pass

    arr_start = text.find("[")
    arr_end = text.rfind("]")

    if arr_start >= 0 and arr_end > arr_start:
        return json.loads(text[arr_start : arr_end + 1])

    raise ValueError("Model returned invalid JSON")


async def plan_essay(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    instruction = str(context.get("instruction", "")).strip()

    if not instruction:
        raise ValueError("Essay instruction is required")

    result = await model_json(
        """You are the GhostWriter planning agent.
Return ONLY JSON:
{
 "essayTopic": string,
 "essayType": string,
 "thesis": string,
 "paragraphCount": integer,
 "searchQueries": string[],
 "notes": string,
 "essayFocusOptions": string[]
}

essayType must be one of:
Argumentative, Analytical, Expository, Narrative,
Compare-Contrast, Research, Essay.

paragraphCount must be 3-12.
Provide 3-6 searchQueries and 5-8 essayFocusOptions.""",
        f"USER INSTRUCTION:\n{instruction}\n\nNOTES:\n{args.get('notes', '')}",
    )

    count = int(result.get("paragraphCount", 5))
    count = max(3, min(12, count))

    plan = {
        "thesis": str(result.get("thesis", "")),
        "paragraphCount": count,
        "searchQueries": list(result.get("searchQueries", []))[:6],
        "notes": str(result.get("notes", "")),
        "essayFocusOptions": list(result.get("essayFocusOptions", []))[:8],
    }

    context["essayTopic"] = str(
        result.get("essayTopic") or "Untitled topic"
    )
    context["essayType"] = str(result.get("essayType") or "Essay")
    context["plan"] = plan

    return {
        "essayTopic": context["essayTopic"],
        "essayType": context["essayType"],
        "plan": plan,
    }


async def generate_outlines(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    topic = context.get("essayTopic")

    if not topic:
        raise ValueError("Essay topic missing. Call plan_essay first.")

    count = max(3, min(20, int(args.get("count", 5))))
    focus = args.get("selectedFocusAreas", [])

    result = await model_json(
        """You are Lily, an academic outline agent.
Return ONLY JSON:
{
 "outlines": [
   {
     "type": "Introduction|Body Paragraph|Conclusion",
     "title": string,
     "description": string
   }
 ]
}
The first item must be Introduction.
The final item must be Conclusion.
Return exactly the requested number of outlines.""",
        json.dumps(
            {
                "topic": topic,
                "essayType": context.get("essayType"),
                "plan": context.get("plan"),
                "count": count,
                "selectedFocusAreas": focus,
            },
            indent=2,
        ),
        temperature=0.5,
    )

    raw = result.get("outlines", [])
    outlines = []

    for index, item in enumerate(raw[:count]):
        raw_type = str(item.get("type", "")).lower()

        if index == 0 or "introduction" in raw_type:
            outline_type = "Introduction"
        elif index == count - 1 or "conclusion" in raw_type:
            outline_type = "Conclusion"
        else:
            outline_type = "Body Paragraph"

        outlines.append(
            {
                "id": f"outline-{index + 1}",
                "type": outline_type,
                "title": str(item.get("title", "")),
                "description": str(item.get("description", "")),
            }
        )

    if not outlines:
        raise ValueError("No outlines generated")

    context["outlines"] = outlines
    return {"outlines": outlines}


async def evaluate_sources(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    sources = context.get("compactedSources", [])

    if not sources:
        raise ValueError("No compacted sources available")

    result = await model_json(
        """Evaluate whether these sources are sufficient for the essay.
Return ONLY JSON:
{
 "sufficient": boolean,
 "quality": "good"|"fair"|"poor",
 "gaps": string[],
 "recommendation": string
}""",
        json.dumps(
            {
                "topic": context.get("essayTopic"),
                "essayType": context.get("essayType"),
                "outlines": context.get("outlines", []),
                "sources": sources,
                "notes": args.get("notes", ""),
            },
            indent=2,
        ),
        temperature=0.2,
    )

    return {
        "sufficient": bool(result.get("sufficient", len(sources) >= 3)),
        "quality": result.get("quality", "fair"),
        "gaps": result.get("gaps", []),
        "recommendation": result.get("recommendation", ""),
    }


async def write_essay(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    if not context.get("essayTopic"):
        raise ValueError("Essay topic missing")

    if len(context.get("outlines", [])) < 3:
        raise ValueError("At least 3 outlines are required")

    if not context.get("compactedSources"):
        raise ValueError("Compacted sources are required")

    settings = context.get("draftSettings", {})

    if not settings.get("wordCount"):
        raise ValueError("wordCount is required")

    if not settings.get("citationStyle"):
        raise ValueError("citationStyle is required")

    result = await model_json(
        """You are Lucas, the GhostWriter essay drafting agent.
Write the complete academic essay using the supplied outline and sources.

Return ONLY JSON:
{
 "essay_content": string,
 "bibliography": string
}

Follow the requested word count, tone and citation style.
Use only supplied research sources for factual citations.""",
        json.dumps(
            {
                "topic": context.get("essayTopic"),
                "essayType": context.get("essayType"),
                "wordCount": settings.get("wordCount"),
                "citationStyle": settings.get("citationStyle"),
                "tone": settings.get("tone", "academic"),
                "keywords": settings.get("keywords", ""),
                "outlines": context.get("outlines", []),
                "sources": context.get("compactedSources", []),
                "notes": args.get("notes", ""),
            },
            indent=2,
        ),
        temperature=0.4,
    )

    essay = str(result.get("essay_content", "")).strip()

    if not essay:
        raise ValueError("Writer returned no essay content")

    bibliography = str(result.get("bibliography", "")).strip()

    context["essay"] = essay
    context["bibliography"] = bibliography

    return {
        "wordCount": len(essay.split()),
        "bibliographyLength": len(bibliography),
    }