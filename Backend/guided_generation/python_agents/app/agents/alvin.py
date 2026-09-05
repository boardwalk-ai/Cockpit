import json

from app.model_client import ModelClient


SYSTEM_PROMPT = '''
You are Alvin, an expert research assistant for Octopilot.
Find credible, real, scrapable web-page URLs that support the essay topic and
outlines provided. Never fabricate URLs. Prefer universities, government
agencies, journals, recognized news organizations, and think tanks. Do not
return PDFs or social-media URLs.

Return strict JSON as {"results":[...]} where each result contains
website_URL, Title, Author, Published Year, Publisher, and outline_index.
'''.strip()


class AlvinAgent:
    def __init__(self, model_client: ModelClient):
        self.model_client = model_client

    async def search(self, payload: dict) -> list[dict]:
        essay_topic = str(payload.get("essayTopic") or "").strip()
        outlines = payload.get("outlines")
        try:
            target_count = int(payload.get("targetCount") or 0)
        except (TypeError, ValueError):
            target_count = 0

        if not essay_topic or not isinstance(outlines, list) or not outlines:
            raise ValueError("targetCount, essayTopic, and outlines are required")

        target_count = max(1, min(30, target_count or 1))
        numbered = []
        for index, outline in enumerate(outlines, start=1):
            outline = outline if isinstance(outline, dict) else {}
            numbered.append({
                "outline_index": index,
                "type": str(outline.get("type") or ""),
                "title": str(outline.get("title") or ""),
                "description": str(outline.get("description") or ""),
            })

        result = await self.model_client.json_completion(
            SYSTEM_PROMPT,
            f"Number of links needed: {target_count}\n"
            f"Essay Topic: {essay_topic}\n\n"
            f"Supporting Outlines:\n{json.dumps(numbered, indent=2)}",
            0.2,
        )

        raw = result.get("results")
        if not isinstance(raw, list):
            raw = next((v for v in result.values() if isinstance(v, list)), [])

        normalized = []
        seen = set()
        for entry in raw:
            if not isinstance(entry, dict):
                continue
            url = str(entry.get("website_URL") or entry.get("url") or entry.get("link") or "").strip()
            lowered = url.lower()
            if not lowered.startswith(("http://", "https://")):
                continue
            if lowered.split("?", 1)[0].endswith(".pdf") or lowered in seen:
                continue

            item = {
                "website_URL": url,
                "Title": str(entry.get("Title") or entry.get("title") or "").strip(),
                "Author": str(entry.get("Author") or entry.get("author") or "").strip(),
                "Published Year": str(entry.get("Published Year") or entry.get("publishedYear") or entry.get("year") or "").strip(),
                "Publisher": str(entry.get("Publisher") or entry.get("publisher") or entry.get("source") or "").strip(),
            }
            try:
                outline_index = int(entry.get("outline_index") or entry.get("outlineIndex") or entry.get("outline"))
                if outline_index > 0:
                    item["outline_index"] = outline_index
            except (TypeError, ValueError):
                pass

            seen.add(lowered)
            normalized.append(item)
            if len(normalized) >= target_count:
                break

        if not normalized:
            raise ValueError("Alvin returned an empty or invalid source list")
        return normalized
