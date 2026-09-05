import json

from app.model_client import ModelClient


SYSTEM_PROMPT = '''
You are Su, a writing support agent for Octopilot Writing Chamber.
Always return strict JSON only.

MORE IDEAS returns 4-8 prose-ready lines in {"bullets":[...]}.
ASK returns {"answer":"..."} with a direct concise answer.
INTEXT returns {"inTextCitation":[{"index":0,"citation":"..."}]} and preserves indexes.
SUMMARY returns {"done":[...],"suggestions":[...]} based only on supplied writing.
'''.strip()


class SuAgent:
    def __init__(self, model_client: ModelClient):
        self.model_client = model_client

    async def assist(self, payload: dict) -> dict:
        mode = str(payload.get("mode") or "").strip()
        data = payload.get("input")
        if mode not in {"more_ideas", "ask", "intext", "summary"}:
            raise ValueError("invalid Su mode")
        if not isinstance(data, dict):
            raise ValueError("input is required")

        if mode == "more_ideas":
            content = f"Task: MORE IDEAS\nEssay Topic: {data.get('essayTopic') or ''}\nSection Type: {data.get('sectionType') or ''}\nSection Title: {data.get('sectionTitle') or ''}\nCitation Style: {data.get('citationStyle') or ''}\nCurrent Draft:\n{data.get('currentDraft') or ''}"
        elif mode == "ask":
            content = f"Task: ASK\nEssay Topic: {data.get('essayTopic') or ''}\nSection Type: {data.get('sectionType') or ''}\nSection Title: {data.get('sectionTitle') or ''}\nQuestion: {data.get('question') or ''}\nCurrent Draft:\n{data.get('currentDraft') or ''}"
        elif mode == "intext":
            content = f"Task: INTEXT\nCitation Style: {data.get('citationStyle') or ''}\nSources:\n{json.dumps(data.get('sources') or [], indent=2)}"
        else:
            content = f"Task: SUMMARY\nEssay Title: {data.get('essayTitle') or ''}\nOutline Titles:\n{json.dumps(data.get('outlineTitles') or [], indent=2)}\nWritten Essay:\n{data.get('writtenEssay') or ''}"

        result = await self.model_client.json_completion(
            SYSTEM_PROMPT,
            content,
            0.4 if mode == "ask" else 0.5,
        )

        if mode == "more_ideas":
            raw = result.get("bullets")
            if not isinstance(raw, list):
                raw = result.get("lines") if isinstance(result.get("lines"), list) else []
            return {"bullets": [str(x).strip() for x in raw if str(x).strip()]}

        if mode == "ask":
            return {"answer": str(result.get("answer") or "").strip()}

        if mode == "intext":
            normalized = []
            for item in result.get("inTextCitation") or []:
                if not isinstance(item, dict):
                    continue
                try:
                    index = int(item.get("index"))
                except (TypeError, ValueError):
                    continue
                citation = str(item.get("citation") or "").strip()
                if index >= 0 and citation:
                    normalized.append({"index": index, "citation": citation})
            return {"inTextCitation": normalized}

        return {
            "done": [str(x).strip() for x in (result.get("done") or []) if str(x).strip()],
            "suggestions": [str(x).strip() for x in (result.get("suggestions") or []) if str(x).strip()],
        }
