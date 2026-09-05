import unittest

from app.agents.hein import HeinAgent
from app.agents.lily import LilyAgent


class MockJSONClient:
    def __init__(self, result):
        self.result = result
        self.call = None

    async def json_completion(self, system_prompt, user_content, temperature):
        self.call = (system_prompt, user_content, temperature)
        return self.result


class HeinAgentTests(unittest.IsolatedAsyncioTestCase):
    async def test_analyzes_reference_payload(self):
        client = MockJSONClient(
            {
                "analysis": "Analyze policy.",
                "essayTopic": "Energy",
                "essayType": "Analytical",
                "scope": "National policy",
                "structure": "Introduction, body, conclusion",
            }
        )
        result = await HeinAgent(client).analyze(
            {
                "major": "Political Science",
                "essayType": "Analytical",
                "instructions": "Compare energy policy",
            }
        )

        self.assertEqual(result["essayTopic"], "Energy")
        _, user_content, temperature = client.call
        self.assertIn("Major: Political Science", user_content)
        self.assertIn("Compare energy policy", user_content)
        self.assertEqual(temperature, 0.3)

    async def test_requires_text_or_image(self):
        with self.assertRaisesRegex(ValueError, "instructions or an image"):
            await HeinAgent(MockJSONClient({})).analyze({})


class LilyAgentTests(unittest.IsolatedAsyncioTestCase):
    async def test_generates_and_sanitizes_reference_outline(self):
        client = MockJSONClient(
            {
                "outlines": [
                    {
                        "type": "Introduction",
                        "title": "Opening",
                        "bullets": [" Thesis ", "", 4],
                    }
                ]
            }
        )
        result = await LilyAgent(client).generate(
            {
                "analysis": "Analyze policy",
                "essayTopic": "Energy",
                "essayType": "Analytical",
                "mode": "auto",
                "count": 5,
                "bullets": True,
            }
        )

        self.assertEqual(result["outlines"][0]["bullets"], ["Thesis"])
        system_prompt, user_content, temperature = client.call
        self.assertIn("Generate exactly 5 items", system_prompt)
        self.assertIn("Essay Topic: Energy", user_content)
        self.assertEqual(temperature, 0.5)


if __name__ == "__main__":
    unittest.main()
