import os

import httpx


class HumanizerService:
    def __init__(self):
        self.stealthgpt_key = os.getenv("STEALTHGPT_API_KEY", "")
        self.undetectable_key = os.getenv("UNDETECTABLE_API_KEY", "")

    async def stealthgpt(self, payload: dict) -> dict:
        prompt = str(payload.get("prompt") or "").strip()
        rephrase = payload.get("rephrase")

        if not prompt or not isinstance(rephrase, bool):
            raise ValueError("prompt and rephrase are required")

        if not self.stealthgpt_key:
            raise RuntimeError("STEALTHGPT_API_KEY is not configured")

        education_level = payload.get("educationLevel")
        if education_level == "High School":
            tone = "HighSchool"
        elif education_level == "PHD":
            tone = "PhD"
        else:
            tone = education_level or "Standard"

        body = {
            "prompt": prompt,
            "rephrase": rephrase,
            "tone": tone,
            "mode": payload.get("strength") or "Medium",
            "detector": payload.get("detector") or "GPTZero",
        }

        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                "https://www.stealthgpt.ai/api/stealthify",
                headers={
                    "Content-Type": "application/json",
                    "api-token": self.stealthgpt_key,
                },
                json=body,
            )

        response.raise_for_status()
        return response.json()

    async def undetectable(self, payload: dict) -> dict:
        content = str(payload.get("content") or "").strip()
        readability = str(payload.get("readability") or "").strip()
        purpose = str(payload.get("purpose") or "").strip()
        strength = str(payload.get("strength") or "").strip()

        if not content or not readability or not purpose or not strength:
            raise ValueError(
                "content, readability, purpose, and strength are required"
            )

        if not self.undetectable_key:
            raise RuntimeError("UNDETECTABLE_API_KEY is not configured")

        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                "https://humanize.undetectable.ai/submit",
                headers={
                    "Content-Type": "application/json",
                    "apikey": self.undetectable_key,
                },
                json={
                    "content": content,
                    "readability": readability,
                    "purpose": purpose,
                    "strength": strength,
                    "model": "v11",
                },
            )

        response.raise_for_status()
        return response.json()

    async def undetectable_document(self, document_id: str) -> dict:
        document_id = document_id.strip()

        if not document_id:
            raise ValueError("document id is required")

        if not self.undetectable_key:
            raise RuntimeError("UNDETECTABLE_API_KEY is not configured")

        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                "https://humanize.undetectable.ai/document",
                headers={
                    "Content-Type": "application/json",
                    "apikey": self.undetectable_key,
                },
                json={"id": document_id},
            )

        response.raise_for_status()
        return response.json()
