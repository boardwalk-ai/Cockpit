import os
from typing import Any

import httpx


async def humanize_essay(
    args: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    essay = str(context.get("essay", "")).strip()
    if not essay:
        raise ValueError("Essay is required")

    provider = args.get("provider") or "StealthGPT"

    if provider == "StealthGPT":
        key = os.getenv("STEALTHGPT_API_KEY")

        if not key:
            context["humanizedContent"] = essay
            context["humanizerProvider"] = provider
            context["humanizeProvider"] = provider
            return {"provider": provider, "fallback": True}

        async with httpx.AsyncClient(timeout=180) as client:
            response = await client.post(
                "https://stealthgpt.ai/api/stealthify",
                headers={
                    "api-token": key,
                    "Content-Type": "application/json",
                },
                json={
                    "prompt": essay,
                    "rephrase": True,
                },
            )
            response.raise_for_status()
            data = response.json()

        content = str(
            data.get("result")
            or data.get("output")
            or data.get("text")
            or essay
        )

    else:
        key = os.getenv("UNDETECTABLE_API_KEY")

        if not key:
            context["humanizedContent"] = essay
            context["humanizerProvider"] = provider
            context["humanizeProvider"] = provider
            return {"provider": provider, "fallback": True}

        async with httpx.AsyncClient(timeout=180) as client:
            response = await client.post(
                "https://humanize.undetectable.ai/submit",
                headers={
                    "apikey": key,
                    "Content-Type": "application/json",
                },
                json={"content": essay},
            )
            response.raise_for_status()
            data = response.json()

        content = str(
            data.get("output")
            or data.get("text")
            or data.get("humanized")
            or essay
        )

    context["humanizedContent"] = content
    context["humanizerProvider"] = provider
    context["humanizeProvider"] = provider

    return {
        "provider": provider,
        "length": len(content),
    }