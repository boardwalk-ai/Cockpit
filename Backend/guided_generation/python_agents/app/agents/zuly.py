from app.model_client import ModelClient


BASE_PROMPT = '''
You are Zuly, a precision analysis agent for Octopilot.

SOURCE_COMPACTION:
Compact raw research content into citation-ready evidence. Preserve useful
arguments, findings, statistics, and quotes. Remove fluff and boilerplate.
Never invent facts or quotes.

WRITING_STYLE_ANALYSIS:
Describe observable sentence rhythm, paragraph movement, tone, grammar habits,
vocabulary habits, and recurring weakness patterns. Do not give advice.

Always return strict JSON only.
'''.strip()


class ZulyAgent:
    def __init__(self, model_client: ModelClient):
        self.model_client = model_client

    async def run(self, payload: dict) -> dict:
        task = "writing_style_analysis" if payload.get("task") == "writing_style_analysis" else "source_compaction"

        if task == "source_compaction":
            full_content = str(payload.get("fullContent") or "").strip()
            if not full_content:
                raise ValueError("fullContent is required")

            result = await self.model_client.json_completion(
                BASE_PROMPT + '\nReturn exactly: compacted_content, key_points, relevant_quotes.',
                "Task: SOURCE_COMPACTION\n"
                f"Source Type: {payload.get('sourceType') or 'unknown'}\n"
                f"Source Title: {payload.get('sourceTitle') or 'Unknown'}\n\n"
                f"Full Content:\n{full_content}",
                0.2,
            )
            return {
                "compacted_content": str(result.get("compacted_content") or "").strip(),
                "key_points": [str(x).strip() for x in (result.get("key_points") or []) if str(x).strip()],
                "relevant_quotes": [str(x).strip() for x in (result.get("relevant_quotes") or []) if str(x).strip()],
            }

        extracted_text = str(payload.get("extractedText") or "").strip()
        images = [x for x in (payload.get("pageImages") or []) if isinstance(x, str) and x.strip()]
        if not extracted_text and not images:
            raise ValueError("extractedText or pageImages is required")

        if images:
            content = [{
                "type": "text",
                "text": "Task: WRITING_STYLE_ANALYSIS\n"
                        f"Uploaded File: {payload.get('fileName') or 'Unknown'}\n"
                        "Analyze the attached pages and return only JSON."
            }]
            content.extend({"type": "image_url", "image_url": {"url": image}} for image in images)
        else:
            content = "Task: WRITING_STYLE_ANALYSIS\n"                       f"Uploaded File: {payload.get('fileName') or 'Unknown'}\n\n"                       f"Extracted Writing Sample:\n{extracted_text}"

        result = await self.model_client.json_completion(
            BASE_PROMPT + '\nReturn exactly: writing_style, grammar_usage_style, vocabulary_usage_style_and_level, common_mistakes.',
            content,
            0.2,
        )
        return {
            "writing_style": str(result.get("writing_style") or "").strip(),
            "grammar_usage_style": str(result.get("grammar_usage_style") or "").strip(),
            "vocabulary_usage_style_and_level": str(result.get("vocabulary_usage_style_and_level") or "").strip(),
            "common_mistakes": [str(x).strip() for x in (result.get("common_mistakes") or []) if str(x).strip()],
        }
