# Octopilot voices

The main chat speaks with Kyutai **Pocket TTS** (model CC BY 4.0). Six voices,
each cloned once from a public-domain (CC0) recording from Kyutai's
[voice donations](https://huggingface.co/kyutai/tts-voices); see `voices.json`.
They stand in until a contracted voice actor is recorded.

| Voice | Source (CC0) | Orb |
|---|---|---|
| Marc | voice-donations/0a67 | red → coral |
| Noah | voice-donations/1410 | blue → cyan |
| Lucas | voice-donations/29da | green → mint |
| Sarah | voice-donations/3973 | pink → peach |
| Lucy | voice-donations/4b70 | violet → lilac |
| Dasha | voice-donations/9a66 | amber → orange |

```bash
pip install pocket-tts fastapi uvicorn
hf auth login                 # the gated kyutai/pocket-tts weights (cloning)
python build_voices.py        # -> voices/<id>.safetensors (~6 MB each, not committed)
python serve.py               # dev TTS server on http://127.0.0.1:8792
```

The voice files work with the ungated `kyutai/pocket-tts-without-voice-cloning`
weights, which refuse to clone from audio: the app ships those plus our voice
files, never a recording, and users cannot clone voices.

Attribution: Pocket TTS by Kyutai (CC BY 4.0).
