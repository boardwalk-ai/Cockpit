import json
import os
from collections.abc import AsyncIterator

import httpx


OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"


class ModelClient:
    def __init__(
        self,
        model_env: str = "OPENROUTER_MODEL",
        default_model: str = "openai/gpt-4o-mini",
    ):
        self.api_key = os.getenv("OPENROUTER_API_KEY", "")
        self.model = os.getenv(
            model_env,
            os.getenv("OPENROUTER_MODEL", default_model),
        )

    async def json_completion(
        self,
        system_prompt: str,
        user_content,
        temperature: float,
    ) -> dict:
        if not self.api_key:
            raise RuntimeError("OPENROUTER_API_KEY is not configured")

        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
            "temperature": temperature,
            "response_format": {"type": "json_object"},
        }

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://octopilotai.com",
            "X-Title": "OctoPilot AI",
        }

        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                OPENROUTER_URL,
                headers=headers,
                json=payload,
            )
            response.raise_for_status()

        data = response.json()
        content = data["choices"][0]["message"]["content"]

        return json.loads(content)

    async def stream_completion(
        self,
        system_prompt: str,
        user_content,
        temperature: float,
    ) -> AsyncIterator[str]:
        if not self.api_key:
            raise RuntimeError("OPENROUTER_API_KEY is not configured")

        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
            "temperature": temperature,
            "stream": True,
            "response_format": {"type": "json_object"},
        }
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://octopilotai.com",
            "X-Title": "OctoPilot AI",
        }

        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream(
                "POST",
                OPENROUTER_URL,
                headers=headers,
                json=payload,
            ) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line.startswith("data:"):
                        continue

                    chunk = line[len("data:") :].strip()
                    if chunk == "[DONE]":
                        break

                    try:
                        data = json.loads(chunk)
                        delta = data["choices"][0]["delta"].get("content")
                    except (json.JSONDecodeError, KeyError, IndexError, TypeError):
                        continue

                    if delta:
                        yield delta
