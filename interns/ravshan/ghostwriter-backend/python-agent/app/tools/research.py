import json
import os
from typing import Any
from urllib.parse import quote

import httpx

from .core import model_json


async def search_sources(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    topic = context.get("essayTopic")
    outlines = context.get("outlines", [])

    if not topic:
        raise ValueError("Essay topic missing")

    if not outlines:
        raise ValueError("Outlines missing")

    count = max(3, min(20, int(args.get("count", 5))))
    refinement = str(args.get("refinement", "")).strip()

    result = await model_json(
        """You are Alvin, a research source discovery agent.
Return ONLY JSON:
{
  "results": [
    {
      "title": string,
      "url": string,
      "author": string,
      "publishedYear": string,
      "publisher": string
    }
  ]
}
Return credible HTTP/HTTPS sources only. Do not return PDFs.""",
        json.dumps(
            {
                "topic": topic,
                "essayType": context.get("essayType"),
                "outlines": outlines,
                "count": count,
                "refinement": refinement,
            },
            indent=2,
        ),
        temperature=0.2,
    )

    raw = result.get("results", [])
    existing = {
        str(x.get("url", "")).lower()
        for x in context.get("searchResults", [])
    }

    added = []

    for item in raw:
        url = str(item.get("url", "")).strip()

        if not url.startswith(("http://", "https://")):
            continue

        if url.lower().endswith(".pdf"):
            continue

        if url.lower() in existing:
            continue

        row = {
            "title": str(item.get("title", "")),
            "url": url,
            "author": str(item.get("author", "")),
            "publishedYear": str(item.get("publishedYear", "")),
            "publisher": str(item.get("publisher", "")),
        }

        added.append(row)
        existing.add(url.lower())

        if len(added) >= count:
            break

    if not added:
        raise ValueError("No new sources found. Try a different refinement.")

    context.setdefault("searchResults", []).extend(added)

    return {
        "added": len(added),
        "totalInContext": len(context["searchResults"]),
    }


async def scrape_sources(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    limit = max(1, min(30, int(args.get("limit", 5))))

    requested_urls = args.get("urls") or []

    already = {
        str(x.get("url", "")).lower()
        for x in context.get("scrapedSources", [])
    }

    candidates = []

    if requested_urls:
        for url in requested_urls:
            match = next(
                (
                    x
                    for x in context.get("searchResults", [])
                    if str(x.get("url", "")).lower() == str(url).lower()
                ),
                None,
            )

            candidates.append(
                match
                or {
                    "title": str(url),
                    "url": str(url),
                }
            )
    else:
        candidates = [
            x
            for x in context.get("searchResults", [])
            if str(x.get("url", "")).lower() not in already
        ]

    candidates = candidates[:limit]

    scraped = 0
    failed = 0

    async with httpx.AsyncClient(timeout=15) as client:
        for source in candidates:
            url = str(source.get("url", "")).strip()

            try:
                response = await client.get(
                    f"https://api.octopilotai.com/api/scrape?url={quote(url, safe='')}"
                )

                response.raise_for_status()
                data = response.json()

                content = ""
                title = source.get("title", "")
                publisher = source.get("publisher", "")

                references = data.get("references")

                if isinstance(references, list) and references:
                    ref = references[0]

                    content = str(
                        ref.get("rawContent")
                        or ref.get("fullContent")
                        or ""
                    )

                    title = ref.get("title") or title
                    publisher = ref.get("publisher") or publisher
                else:
                    content = str(data.get("fullContent") or "")
                    title = data.get("title") or title
                    publisher = data.get("publisher") or publisher

                if not content.strip():
                    failed += 1
                    continue

                context.setdefault("scrapedSources", []).append(
                    {
                        "title": title,
                        "url": url,
                        "author": source.get("author", ""),
                        "publishedYear": source.get("publishedYear", ""),
                        "publisher": publisher,
                        "fullContent": content,
                    }
                )

                scraped += 1

            except Exception:
                failed += 1

    return {
        "scraped": scraped,
        "failed": failed,
        "totalInContext": len(context.get("scrapedSources", [])),
    }


async def compact_sources(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    selected_urls = {
        str(x).lower().strip()
        for x in (args.get("urls") or [])
    }

    existing = {
        str(x.get("url", "")).lower()
        for x in context.get("compactedSources", [])
    }

    rejected = {
        str(x.get("url", "")).lower()
        for x in context.get("sourceReviewNotes", [])
        if x.get("rejected")
    }

    targets = []

    for source in context.get("scrapedSources", []):
        url = str(source.get("url", "")).lower()

        if url in existing or url in rejected:
            continue

        if selected_urls and url not in selected_urls:
            continue

        targets.append(source)

    compacted = 0
    failed = 0

    for source in targets:
        try:
            result = await model_json(
                """You are Zuly, a source compression agent.

Return ONLY JSON:
{
  "compacted_content": string,
  "key_points": string[],
  "relevant_quotes": string[]
}

Keep facts, arguments and citation-useful details relevant to the essay.""",
                json.dumps(
                    {
                        "essayTopic": context.get("essayTopic"),
                        "source": {
                            "title": source.get("title"),
                            "url": source.get("url"),
                            "fullContent": source.get("fullContent"),
                        },
                    },
                    indent=2,
                ),
                temperature=0.2,
            )

            sections = [
                str(result.get("compacted_content", "")).strip()
            ]

            points = result.get("key_points", [])
            quotes = result.get("relevant_quotes", [])

            if points:
                sections.append(
                    "Key points:\n" +
                    "\n".join(f"- {x}" for x in points)
                )

            if quotes:
                sections.append(
                    "Relevant quotes:\n" +
                    "\n".join(f"- {x}" for x in quotes)
                )

            summary = "\n\n".join(
                section for section in sections if section
            )

            context.setdefault("compactedSources", []).append(
                {
                    "title": source.get("title", ""),
                    "url": source.get("url", ""),
                    "author": source.get("author", ""),
                    "publishedYear": source.get("publishedYear", ""),
                    "publisher": source.get("publisher", ""),
                    "summary": summary,
                }
            )

            compacted += 1

        except Exception:
            failed += 1

    return {
        "compacted": compacted,
        "failed": failed,
        "totalInContext": len(context.get("compactedSources", [])),
    }