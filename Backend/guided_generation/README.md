# Guided Generation backend

Guided Generation is a two-language backend:

- Go exposes the public API, durable essay/thread and folder persistence,
  per-user credits, and Python-agent proxying on port `8200`.
- Python runs the rewritten Hein, Lily, and Lucas agents and OpenRouter calls on
  port `8201`.

The generation pipeline is Hein assignment analysis → Lily outline generation
→ Lucas source-grounded essay streaming.

## Run locally

From `python_agents`:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
$env:OPENROUTER_API_KEY = "your-key"
$env:OPENROUTER_PRIMARY_MODEL = "openai/gpt-4o-mini"
$env:OPENROUTER_SECONDARY_MODEL = "openai/gpt-4o-mini"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --port 8201
```

From `go_api` in a second terminal:

```powershell
$env:PYTHON_AGENT_URL = "http://localhost:8201"
$env:GUIDED_GENERATION_DATA_PATH = "data/guided_generation.json"
$env:DEFAULT_USER_CREDITS = "1000"
go run .\cmd\server
```

`GUIDED_GENERATION_DATA_PATH` is a durable JSON data file. A blank path creates
an in-memory store for tests. `DEFAULT_USER_CREDITS` seeds a user's balance the
first time it is loaded. The storage implementation is isolated behind the Go
`store` package so production can replace JSON with its confirmed database
schema without changing API handlers.

For per-user isolation, deployments should send a trusted `X-User-ID` header.
When only `Authorization` is present, the service stores a one-way hash of that
value as the user key. Requests without either header use `dev-user` for local
development.

## Public Go API

Agent routes:

- `POST /api/guided-generation/analyze`
- `POST /api/guided-generation/outlines`
- `POST /api/guided-generation/generate` (`text/event-stream`)

OctopilotWeb-compatible persistence routes:

- `GET|POST /api/v1/ghostwriter/threads`
- `GET|PATCH|DELETE /api/v1/ghostwriter/threads/{threadId}`
- `GET|POST /api/v1/ghostwriter/folders`
- `PATCH|DELETE /api/v1/ghostwriter/folders/{folderId}`

Credit routes:

- `GET /api/v1/me/credits`
- `POST /api/v1/me/credits/deduct`
- `GET /api/guided-generation/credits` (convenience alias)
- `POST /api/guided-generation/credits/deduct` (convenience alias)

Credit deductions accept `credit_type`, `amount`, and an optional stable
`idempotency_key`. Reusing a key returns the original result without charging
twice. Insufficient balances return HTTP `402`.

## Lucas contract

Lucas accepts either a direct object or the reference frontend's
`{"organizerState": {...}}` wrapper. It supports `selectedOutlines`,
`compactedSources`, exact word count, keywords, rubric criteria, normal
writing-style preferences, tone, and citation style. Legacy frontend aliases
such as `outlines`, `sources`, `selectedSources`, `outline`, and `citation` are
also accepted.

```json
{
  "organizerState": {
    "analysis": "What the assignment requires",
    "essayTopic": "Renewable energy policy",
    "essayType": "Comparative",
    "wordCount": 1200,
    "keywords": "policy tradeoffs",
    "tone": "Academic",
    "citationStyle": "APA",
    "selectedOutlines": [
      {
        "type": "Introduction",
        "title": "Policy tradeoffs",
        "description": "Introduce the comparison"
      }
    ],
    "compactedSources": [
      {
        "kind": "report",
        "title": "Energy Outlook",
        "publisher": "Example Institute",
        "author": "A. Researcher",
        "publishedYear": "2025",
        "compactedContent": "Relevant source evidence"
      }
    ],
    "rubricCriteria": [
      {
        "name": "Evidence",
        "points": 20,
        "description": "Support the thesis with credible sources"
      }
    ]
  }
}
```

The concatenated `delta.text` values form strict Lucas JSON:

```json
{
  "essay_content": "The essay with in-text citations",
  "bibliography": "The formatted bibliography"
}
```

The stream uses named SSE events:

```text
event: delta
data: {"text":"generated JSON fragment"}

event: meta
data: {"model":"openai/gpt-4o-mini"}

event: done
data: {}
```

The agent uses every supplied source where relevant, follows the exact paragraph
order, respects word count and rubric constraints, and does not invent missing
source details. Humanizer and detection-evasion behavior is intentionally not
part of Lucas.

## Tests

```powershell
cd python_agents
.\.venv\Scripts\python.exe -m unittest discover -s tests -v

cd ..\go_api
go test ./...
```

`tests/e2e_app.py` provides deterministic mock agents for a real-process
Go-to-Python integration smoke test without spending OpenRouter credits.


## Additional Guided Generation agents

The Python service also rewrites Alvin (source discovery), Zuly (source compaction and writing-style analysis), Spoonie (citations/OCR), Su (Writing Chamber assistance), and Octo (in-app navigation). The existing Humanizer adapters are wired into the service as well.

The Go API exposes compatible public routes for `/api/alvin/search`, `/api/zuly/compact`, `/api/spoonie/citation`, `/api/su/assist`, `/api/octo/assist`, and the three `/api/humanize/*` routes while Python owns the AI/model work.
