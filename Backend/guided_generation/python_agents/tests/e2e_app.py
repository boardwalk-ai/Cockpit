"""Deterministic FastAPI app used by the Go-to-Python integration smoke test."""

from app import main


class MockHein:
    async def analyze(self, payload):
        return {
            "analysis": "Analyze the supplied topic.",
            "essayTopic": payload.get("instructions") or "Test topic",
            "essayType": "Analytical",
            "scope": "Configured scope",
            "structure": "Introduction, body, conclusion",
        }


class MockLily:
    async def generate(self, payload):
        return {
            "outlines": [
                {
                    "type": "Introduction",
                    "title": "Opening",
                    "description": "Introduce the topic.",
                    "bullets": [],
                }
            ]
        }


class MockLucas:
    async def generate_stream(self, payload):
        yield '{"essay_content":"Integration essay",'
        yield '"bibliography":"Integration source"}'


main.hein = MockHein()
main.lily = MockLily()
main.lucas = MockLucas()
app = main.app
