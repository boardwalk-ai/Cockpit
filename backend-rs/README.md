# octopilot-rs

The Octopilot backend, in Rust (axum). A separate service from the FastAPI
`Backend/` — it takes over the **stateless tools**, **source search**, and
**outline** work, reusing the same Firebase auth. No credits are charged yet.

## Run

```bash
cd backend-rs
cp .env.example .env   # optional; sensible defaults are built in
cargo run
```

Listens on `http://0.0.0.0:8787`.

## Endpoints (v1)

| Method | Path              | Notes                                             |
|--------|-------------------|---------------------------------------------------|
| GET    | `/health`         | liveness                                          |
| GET    | `/v1/dictionary?word=` | dictionaryapi.dev → `DictResult`             |
| GET    | `/v1/thesaurus?word=`  | datamuse → `ThesResult`                      |
| POST   | `/v1/paraphrase`  | `{text}` → `{text}` (undetectable.ai; passthrough without a key) |
| GET    | `/v1/scrape?url=` | upstream page scrape → `Source`                   |
| POST   | `/v1/sources/search` | `{topic, outlines?, keyword?, targetCount?}` → `Source[]` (OpenRouter + scrape; 503 without `OPENROUTER_API_KEY`) |
| GET    | `/v1/me`          | Firebase-authed whoami                             |

JSON shapes match the Flutter `DictResult` / `ThesResult` models, so the client
deserializes them directly.

## Auth

Send a Firebase ID token as `Authorization: Bearer <token>` — verified against
Google's public keys for project `FIREBASE_PROJECT_ID` (RS256, `aud`/`iss`), the
same way the FastAPI does. With `FIREBASE_PROJECT_ID` empty, auth is disabled and
the `X-User-Id` header is trusted (local dev). The free tools are public.

## Next

- Source search + scrape (`/v1/sources/search`, streaming) — from `searchAndScrape`.
- Outline / assignment analysis (OpenRouter).
