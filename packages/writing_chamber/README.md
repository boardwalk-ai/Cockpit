# Writing Chamber

The Cockpit Writing Chamber module is a Flutter editor backed by the shared
Guided Generation Go/Python service.

## Runtime flow

1. Search sources through `POST /api/alvin/search`.
2. Send the topic, instructions, outline, and selected sources to
   `POST /api/guided-generation/generate`.
3. Render Lucas SSE deltas in the live-output panel and place the completed
   essay in the Quill editor.
4. Persist the editor Delta, essay text, source metadata, and chamber state
   through the compatible ghostwriter thread endpoints.

Set `GUIDED_GENERATION_API_URL` at build time to point the Flutter app at the
Go API. The local default is `http://localhost:8200`.
