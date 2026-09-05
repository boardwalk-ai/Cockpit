from app.model_client import ModelClient


SYSTEM_PROMPT = """
You are Hein, an academic assignment analysis agent.

Analyze the student's assignment instructions, selected major, essay type,
and any attached assignment images.

Return only valid JSON with these fields:

analysis: a short summary of what the assignment requires
essayTopic: the primary topic
essayType: the appropriate essay type
scope: the boundaries and focus of the essay
structure: the recommended organization of the essay
""".strip()


class HeinAgent:
    def __init__(self, model_client: ModelClient):
        self.model_client = model_client

    async def analyze(self, payload: dict) -> dict:
        instructions = str(payload.get("instructions") or "").strip()
        images = payload.get("imageDataUrls") or []

        if not instructions and not images:
            raise ValueError("instructions or an image is required")

        text = (
            f"Major: {payload.get('major') or 'Not specified'}\n"
            f"Essay Type: {payload.get('essayType') or 'Not specified'}\n\n"
            f"Assignment Instructions:\n"
            f"{instructions or '(See attached images)'}"
        )

        if images:
            content = [
                {
                    "type": "image_url",
                    "image_url": {"url": image},
                }
                for image in images
                if isinstance(image, str) and image.startswith("data:")
            ]
            content.append({"type": "text", "text": text})
        else:
            content = text

        result = await self.model_client.json_completion(
            SYSTEM_PROMPT,
            content,
            0.3,
        )

        return {
            "analysis": result.get("analysis", ""),
            "essayTopic": result.get("essayTopic", ""),
            "essayType": result.get("essayType", ""),
            "scope": result.get("scope", ""),
            "structure": result.get("structure", ""),
        }
