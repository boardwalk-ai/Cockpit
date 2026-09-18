import json

from app.model_client import ModelClient


BASE_PROMPT = '''
You are Spoonie, a citation and OCR utility agent for Octopilot.
Always return strict JSON only.

CITATION_PREVIEW returns {"citation":"..."}.
OCR_EXTRACT returns {"extracted_text":"..."} and only visible text.
FIELDWORK_CITATION returns {"citation":"..."} using supplied fieldwork metadata.
CITATION_FULL returns {"inText":"...","bibliography":"..."}.

Use supplied metadata only. Never invent missing dates, authors, or publishers.
'''.strip()


class SpoonieAgent:
    def __init__(self, model_client: ModelClient):
        self.model_client = model_client

    async def run(self, payload: dict) -> dict:
        input_data = payload.get("input")
        if not isinstance(input_data, dict):
            raise ValueError("input is required")

        task = str(payload.get("task") or "CITATION_PREVIEW").upper()
        if task not in {"OCR_EXTRACT", "CITATION_PREVIEW", "FIELDWORK_CITATION", "CITATION_FULL"}:
            task = "CITATION_PREVIEW"

        if task == "OCR_EXTRACT":
            image_url = str(input_data.get("imageDataUrl") or "").strip()
            if not image_url:
                raise ValueError("imageDataUrl is required")
            result = await self.model_client.json_completion(
                BASE_PROMPT + '\nReturn exactly one key: extracted_text.',
                [
                    {"type": "text", "text": "Task: OCR_EXTRACT\nRead the attached image."},
                    {"type": "image_url", "image_url": {"url": image_url}},
                ],
                0.2,
            )
            extracted = str(result.get("extracted_text") or "").strip()
            if not extracted:
                raise ValueError("model returned invalid OCR output")
            return {"extracted_text": extracted}

        result = await self.model_client.json_completion(
            BASE_PROMPT,
            f"Task: {task}\nInput:\n{json.dumps(input_data, indent=2)}",
            0.2,
        )

        if task == "CITATION_FULL":
            in_text = str(result.get("inText") or "").strip()
            bibliography = str(result.get("bibliography") or "").strip()
            if not in_text or not bibliography:
                raise ValueError("model returned incomplete citation output")
            return {"inText": in_text, "bibliography": bibliography}

        citation = str(result.get("citation") or "").strip()
        if not citation:
            raise ValueError("model returned empty citation output")
        return {"citation": citation}
