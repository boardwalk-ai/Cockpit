import unittest

from fastapi.testclient import TestClient

import app.main as main
from app.agents.alvin import AlvinAgent
from app.agents.octo import OctoAgent
from app.agents.spoonie import SpoonieAgent
from app.agents.su import SuAgent
from app.agents.zuly import ZulyAgent


class FakeModelClient:
    def __init__(self, results):
        self.results = list(results)
        self.model = "test-model"

    async def json_completion(self, system_prompt, user_content, temperature):
        return self.results.pop(0)


class SupportAgentTests(unittest.IsolatedAsyncioTestCase):
    async def test_alvin_normalizes_results(self):
        agent = AlvinAgent(FakeModelClient([{"results": [
            {"website_URL": "https://example.edu/a", "Title": "A", "outline_index": 1},
            {"website_URL": "https://example.edu/a", "Title": "duplicate"},
            {"website_URL": "https://example.edu/paper.pdf", "Title": "pdf"},
        ]}]))
        result = await agent.search({
            "targetCount": 3,
            "essayTopic": "Topic",
            "outlines": [{"title": "Intro"}],
        })
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["website_URL"], "https://example.edu/a")

    async def test_zuly_tasks(self):
        agent = ZulyAgent(FakeModelClient([
            {"compacted_content": "Compact", "key_points": ["One"], "relevant_quotes": ["Quote"]},
            {"writing_style": "Direct", "grammar_usage_style": "Standard", "vocabulary_usage_style_and_level": "Academic", "common_mistakes": ["Repetition"]},
        ]))
        compacted = await agent.run({"task": "source_compaction", "fullContent": "Long source"})
        style = await agent.run({"task": "writing_style_analysis", "extractedText": "Sample"})
        self.assertEqual(compacted["compacted_content"], "Compact")
        self.assertEqual(style["common_mistakes"], ["Repetition"])

    async def test_spoonie_full_citation(self):
        agent = SpoonieAgent(FakeModelClient([{
            "inText": "(Smith, 2024)",
            "bibliography": "Smith, J. (2024). Example.",
        }]))
        result = await agent.run({"task": "CITATION_FULL", "input": {"style": "APA"}})
        self.assertEqual(result["inText"], "(Smith, 2024)")

    async def test_su_modes(self):
        agent = SuAgent(FakeModelClient([
            {"bullets": ["Idea one."]},
            {"answer": "Answer."},
            {"inTextCitation": [{"index": 0, "citation": "(A, 2024)"}]},
            {"done": ["Done"], "suggestions": ["Improve"]},
        ]))
        self.assertEqual((await agent.assist({"mode": "more_ideas", "input": {}}))["bullets"], ["Idea one."])
        self.assertEqual((await agent.assist({"mode": "ask", "input": {}}))["answer"], "Answer.")
        self.assertEqual((await agent.assist({"mode": "intext", "input": {}}))["inTextCitation"][0]["index"], 0)
        self.assertEqual((await agent.assist({"mode": "summary", "input": {}}))["suggestions"], ["Improve"])

    async def test_octo(self):
        agent = OctoAgent(FakeModelClient([{"answer": "Open Configuration."}]))
        result = await agent.assist({"question": "Where do I add sources?"})
        self.assertEqual(result["answer"], "Open Configuration.")


class RouteRegistrationTests(unittest.TestCase):
    def test_routes_are_registered(self):
        def collect_paths(routes):
            paths = set()

            for route in routes:
                route_path = getattr(route, "path", None)
                if route_path:
                    paths.add(route_path)

                nested = getattr(route, "routes", None)
                if nested:
                    paths.update(collect_paths(nested))

                original_router = getattr(route, "original_router", None)
                if original_router is not None:
                    original_routes = getattr(original_router, "routes", None)
                    if original_routes:
                        paths.update(collect_paths(original_routes))

                app = getattr(route, "app", None)
                app_routes = getattr(app, "routes", None)
                if app_routes:
                    paths.update(collect_paths(app_routes))

            return paths

        paths = collect_paths(main.app.routes)
        expected = {
            "/agents/hein/analyze",
            "/agents/lily/generate",
            "/agents/lucas/generate",
            "/agents/alvin/search",
            "/agents/zuly/compact",
            "/agents/spoonie/citation",
            "/agents/su/assist",
            "/agents/octo/assist",
            "/humanizer/stealthgpt",
            "/humanizer/undetectable",
            "/humanizer/undetectable/document",
        }
        self.assertTrue(expected.issubset(paths))

    def test_validation(self):
        with TestClient(main.app) as client:
            response = client.post("/agents/alvin/search", json={})
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main()
