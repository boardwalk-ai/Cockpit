from app.model_client import ModelClient


def build_system_prompt(
    mode: str,
    requested_type: str | None,
    custom_title: str | None,
    count: int,
    bullets: bool,
) -> str:
    item_format = (
        'Each item must contain "type", "title", and "bullets". '
        '"bullets" must contain 3 to 5 concise phrases.'
        if bullets
        else
        'Each item must contain "type", "title", and "description". '
        '"description" should contain 2 to 3 sentences.'
    )

    prompt = f"""
You are Lily, an academic outline generation agent.

Return only valid JSON with an "outlines" array.

The allowed outline types are:
Introduction
Body Paragraph
Conclusion

{item_format}
""".strip()

    if mode == "auto":
        total = max(3, min(20, count))
        body_count = total - 2
        prompt += (
            f"\nGenerate exactly {total} items: "
            f"1 Introduction, {body_count} Body Paragraph items, "
            "and 1 Conclusion, in that order."
        )

    elif mode == "build":
        prompt += (
            f'\nGenerate exactly one "{requested_type}" item. '
            f'The requested focus is "{custom_title or ""}".'
        )

    elif mode == "single":
        prompt += (
            f'\nGenerate exactly one "{requested_type}" item.'
        )

    return prompt


class LilyAgent:
    def __init__(self, model_client: ModelClient):
        self.model_client = model_client

    async def generate(self, payload: dict) -> dict:
        mode = str(payload.get("mode") or "auto")
        requested_type = payload.get("requestedType")
        custom_title = payload.get("customTitle")

        try:
            count = int(payload.get("count") or 5)
        except (TypeError, ValueError):
            count = 5

        bullets = bool(payload.get("bullets", False))

        system_prompt = build_system_prompt(
            mode,
            requested_type,
            custom_title,
            count,
            bullets,
        )

        user_message = (
            f"Essay Topic: {payload.get('essayTopic') or 'Not specified'}\n"
            f"Essay Type: {payload.get('essayType') or 'Not specified'}\n"
            f"Scope: {payload.get('scope') or 'Not specified'}\n"
            f"Structure: {payload.get('structure') or 'Not specified'}\n\n"
            f"Assignment Analysis:\n"
            f"{payload.get('analysis') or 'No analysis available'}"
        )

        result = await self.model_client.json_completion(
            system_prompt,
            user_message,
            0.5,
        )

        outlines = []

        for item in result.get("outlines", []):
            if not isinstance(item, dict):
                continue

            raw_bullets = item.get("bullets", [])
            clean_bullets = [
                bullet.strip()
                for bullet in raw_bullets
                if isinstance(bullet, str) and bullet.strip()
            ]

            outlines.append(
                {
                    "type": item.get("type") or "Body Paragraph",
                    "title": item.get("title") or "",
                    "description": item.get("description") or "",
                    "bullets": clean_bullets,
                }
            )

        return {"outlines": outlines}
