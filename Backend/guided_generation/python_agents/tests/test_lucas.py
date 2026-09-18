import unittest

from app.agents.lucas import LucasAgent


class MockModelClient:
    def __init__(self):
        self.call = None

    async def stream_completion(self, system_prompt, user_content, temperature):
        self.call = (system_prompt, user_content, temperature)
        for chunk in ('{"essay_content":"Opening ', 'paragraph.","bibliography":"Works"}'):
            yield chunk


class LucasAgentTests(unittest.IsolatedAsyncioTestCase):
    async def test_streams_essay_and_builds_grounded_prompt(self):
        client = MockModelClient()
        agent = LucasAgent(client)
        payload = {
            "analysis": "Compare two energy policies.",
            "essayTopic": "Renewable energy policy",
            "essayType": "Comparative",
            "tone": "Persuasive",
            "wordCount": 1200,
            "citationStyle": "MLA",
            "keywords": "policy tradeoffs",
            "rubricCriteria": [
                {"name": "Evidence", "points": 20, "description": "Use sources"}
            ],
            "outlines": [
                {
                    "type": "Introduction",
                    "title": "Policy tradeoffs",
                    "bullets": ["State the thesis"],
                }
            ],
            "sources": [
                {
                    "title": "Energy Outlook",
                    "author": "A. Researcher",
                    "publishedYear": "2025",
                    "publisher": "Example Institute",
                    "kind": "report",
                    "compactedContent": "Renewable capacity increased.",
                }
            ],
        }

        chunks = [chunk async for chunk in agent.generate_stream(payload)]

        self.assertEqual(
            chunks,
            ['{"essay_content":"Opening ', 'paragraph.","bibliography":"Works"}'],
        )
        system_prompt, user_content, temperature = client.call
        self.assertIn("approximately 1200 words", system_prompt)
        self.assertIn("Persuasive", system_prompt)
        self.assertIn("MLA", system_prompt)
        self.assertIn('"essay_content"', system_prompt)
        self.assertIn('"bibliography"', system_prompt)
        self.assertIn("Do not add an essay title", system_prompt)
        self.assertIn("Outline 1 (Introduction): Policy tradeoffs", user_content)
        self.assertIn("Publisher: Example Institute", user_content)
        self.assertIn("Content (compacted): Renewable capacity increased.", user_content)
        self.assertIn("Keywords: policy tradeoffs", user_content)
        self.assertIn("1. Evidence (20 points): Use sources", user_content)
        self.assertEqual(temperature, 0.4)

    async def test_accepts_frontend_aliases_and_defaults(self):
        client = MockModelClient()
        agent = LucasAgent(client)
        payload = {
            "organizerState": {
                "selectedOutlines": [
                    {"type": "Conclusion", "description": "Close the essay"}
                ],
                "compactedSources": [
                    {"title": "Source", "compactedContent": "Evidence"}
                ],
                "tone": "unsupported",
                "length": "unsupported",
                "citation": "unsupported",
                "writingStyleProfile": {
                    "writing_style": "Direct",
                    "vocabulary_usage_style_and_level": "Undergraduate",
                },
            }
        }

        _ = [chunk async for chunk in agent.generate_stream(payload)]

        system_prompt, user_content, _ = client.call
        self.assertIn("approximately 1250 words", system_prompt)
        self.assertIn("Academic", system_prompt)
        self.assertIn("APA", system_prompt)
        self.assertIn("Writing style: Direct", user_content)
        self.assertIn("Vocabulary level: Undergraduate", user_content)

    async def test_requires_outline(self):
        agent = LucasAgent(MockModelClient())
        with self.assertRaisesRegex(ValueError, "outline item"):
            _ = [
                chunk
                async for chunk in agent.generate_stream(
                    {"sources": [{"title": "Source"}]}
                )
            ]

    async def test_requires_source(self):
        agent = LucasAgent(MockModelClient())
        with self.assertRaisesRegex(ValueError, "source"):
            _ = [
                chunk
                async for chunk in agent.generate_stream(
                    {"outlines": [{"title": "Introduction"}]}
                )
            ]


if __name__ == "__main__":
    unittest.main()
