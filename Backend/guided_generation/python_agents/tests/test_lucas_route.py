import unittest

from fastapi.testclient import TestClient

import app.main as main


class MockLucas:
    async def generate_stream(self, payload):
        yield "First "
        yield "sentence."


class LucasRouteTests(unittest.TestCase):
    def test_streams_sse_events_in_order(self):
        original_lucas = main.lucas
        main.lucas = MockLucas()
        try:
            with TestClient(main.app) as client:
                response = client.post("/agents/lucas/generate", json={})
        finally:
            main.lucas = original_lucas

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.headers["content-type"].startswith("text/event-stream"))
        self.assertIn('event: delta\ndata: {"text": "First "}', response.text)
        self.assertIn('event: delta\ndata: {"text": "sentence."}', response.text)
        self.assertIn("event: meta", response.text)
        self.assertTrue(response.text.endswith("event: done\ndata: {}\n\n"))


if __name__ == "__main__":
    unittest.main()
