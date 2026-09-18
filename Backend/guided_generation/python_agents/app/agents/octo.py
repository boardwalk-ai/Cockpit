from app.model_client import ModelClient


SYSTEM_PROMPT = '''
You are Octo, the in-app assistant for Octopilot AI.
Only answer questions about Octopilot AI screens, workflow, navigation, buttons,
features, and behavior. Be concise, practical, and navigation-focused. Use the
user's language. Do not invent features. Return strict JSON as {"answer":"..."}.
'''.strip()

APP_CONTEXT = '''
Octopilot AI has Automation and Manual writing modes. Guided steps include
Writing Style, Major Selection, Essay Type, Instructions, Outlines,
Configuration, Format, Writing Chamber or Generation, Preview, Humanizer,
Editor, and Export. Configuration supports Octopilot Search, manual sources,
and Fieldwork Mode. Alvin finds sources. Spoonie handles citations and OCR.
Zuly compacts sources and analyzes writing style. Lucas generates essays. Su
supports Writing Chamber. Preview is followed by Humanizer, Editor, and Export.
'''.strip()


class OctoAgent:
    def __init__(self, model_client: ModelClient):
        self.model_client = model_client

    async def assist(self, payload: dict) -> dict:
        question = str(payload.get("question") or "").strip()
        if not question:
            raise ValueError("question is required")

        result = await self.model_client.json_completion(
            SYSTEM_PROMPT,
            f"User question: {question}\n"
            f"Current screen: {payload.get('currentPage') or 'Unknown'}\n\n"
            f"Application context:\n{APP_CONTEXT}\n\n"
            f"Runtime state:\n{payload.get('runtimeContext') or ''}",
            0.35,
        )
        answer = str(result.get("answer") or "").strip()
        if not answer:
            raise ValueError("model returned no answer")
        return {"answer": answer}
