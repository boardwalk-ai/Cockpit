"""LLM generation via OpenRouter (OpenAI-compatible chat completions).

Key + model resolution order (prod reuses what octopilot already has):
  1. If the shared DB is configured, read the OpenRouter key from `api_keys`
     (provider='openrouter') and the model from `system_settings.primary_model`.
  2. Otherwise fall back to OPENROUTER_API_KEY / OPENROUTER_MODEL from env.

Citations are prompt-driven: chunks are numbered [1..n] and the model is asked to
cite those numbers. We do not rely on any provider-native citation feature.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from tenacity import retry, stop_after_attempt, wait_exponential

from ..config import get_settings
from ..models.shared import ApiKey, SystemSetting

SYSTEM_PROMPT = (
    "You are the Study Studio tutor. Answer ONLY from the provided context. "
    "Cite the sources you use with bracketed numbers like [1], [2] that match "
    "the context blocks. If the context does not contain the answer, say you "
    "don't have enough material on that topic yet — do not invent facts."
)


async def resolve_credentials(shared: AsyncSession | None) -> tuple[str, str]:
    """Return (api_key, model). Reads from shared DB when available."""
    settings = get_settings()
    api_key = settings.openrouter_api_key
    model = settings.openrouter_model

    if shared is not None:
        row = await shared.execute(
            select(ApiKey.key).where(ApiKey.provider == "openrouter").limit(1)
        )
        found = row.scalar_one_or_none()
        if found:
            api_key = found
        setting = await shared.execute(
            select(SystemSetting.value).where(SystemSetting.key == "primary_model")
        )
        model_val = setting.scalar_one_or_none()
        if model_val:
            model = model_val

    return api_key, model


async def get_setting(
    shared: AsyncSession | None, key: str, default: str = ""
) -> str:
    """Read a value from octopilot `system_settings` (e.g. secondary_model)."""
    if shared is None:
        return default
    row = await shared.execute(
        select(SystemSetting.value).where(SystemSetting.key == key)
    )
    return row.scalar_one_or_none() or default


def build_context_block(chunks: list[str]) -> str:
    return "\n\n".join(f"[{i + 1}] {c}" for i, c in enumerate(chunks))


@retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=8))
async def generate(
    *,
    api_key: str,
    model: str,
    question: str,
    context: str,
    system: str | None = None,
    max_tokens: int | None = None,
    temperature: float = 0.2,
) -> str:
    settings = get_settings()
    if not api_key:
        raise RuntimeError(
            "No OpenRouter API key. Set OPENROUTER_API_KEY or configure "
            "SHARED_DATABASE_URL so the key can be read from api_keys."
        )
    payload: dict = {
        "model": model,
        "messages": [
            {"role": "system", "content": system or SYSTEM_PROMPT},
            {
                "role": "user",
                "content": f"Context:\n{context}\n\nQuestion: {question}",
            },
        ],
        "temperature": temperature,
    }
    if max_tokens is not None:
        payload["max_tokens"] = max_tokens
    async with httpx.AsyncClient(timeout=180) as client:
        resp = await client.post(
            f"{settings.openrouter_base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "HTTP-Referer": "https://cockpit.octopilot.ai",
                "X-Title": "Cockpit Study Studio",
            },
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()
    return data["choices"][0]["message"]["content"]


ASK_STYLE = (
    " You are talking to a student on a phone: answer in short plain "
    "paragraphs (about 150 words unless they ask for more), no headings or "
    "tables, and mark the one or two key terms with **double asterisks**."
)


def ask_messages(
    *,
    question: str,
    context: str,
    history: list[tuple[str, str]] | None = None,
    focus: str | None = None,
) -> list[dict]:
    """The chat for an Ask AI turn: earlier turns (so follow-ups make sense),
    then this question with its retrieved context."""
    system = SYSTEM_PROMPT + ASK_STYLE
    if focus:
        system += f' The student is asking about the topic "{focus}".'
    messages: list[dict] = [{"role": "system", "content": system}]
    for q, a in history or []:
        messages.append({"role": "user", "content": q})
        messages.append({"role": "assistant", "content": a})
    messages.append(
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {question}"}
    )
    return messages


async def generate_stream(
    *,
    api_key: str,
    model: str,
    question: str,
    context: str,
    history: list[tuple[str, str]] | None = None,
    focus: str | None = None,
) -> AsyncIterator[str]:
    """Yield answer text deltas as they arrive (OpenRouter SSE streaming).

    Falls back to a graceful word-by-word canned message when no API key is
    configured, so the endpoint always streams *something* in local dev.
    """
    settings = get_settings()
    if not api_key:
        stub = (
            "The backend isn't connected to an LLM yet, but retrieval is wired. "
            "Set OPENROUTER_API_KEY (or SHARED_DATABASE_URL) to stream grounded, "
            "cited answers from your studio's material."
        )
        for word in stub.split():
            yield word + " "
        return

    payload = {
        "model": model,
        "messages": ask_messages(
            question=question, context=context, history=history, focus=focus
        ),
        "temperature": 0.2,
        "stream": True,
    }
    async with httpx.AsyncClient(timeout=None) as client:
        async with client.stream(
            "POST",
            f"{settings.openrouter_base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "HTTP-Referer": "https://cockpit.octopilot.ai",
                "X-Title": "Cockpit Study Studio",
            },
            json=payload,
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.startswith("data:"):
                    continue
                chunk = line[len("data:") :].strip()
                if chunk == "[DONE]":
                    break
                try:
                    delta = json.loads(chunk)["choices"][0]["delta"].get("content")
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
                if delta:
                    yield delta
