"""A local TTS server for developing the app's voice chat.

Speaks text in one of Octopilot's voices (see build_voices.py) and returns a
whole WAV: the app waits for the reply and its audio, then plays them
together. On phones the same model is meant to run on the device; this
stands in for it until then.

    python serve.py                  # http://127.0.0.1:8792
    python serve.py --host 0.0.0.0   # also reachable from a phone on the Wi-Fi

    GET  /v1/voices            -> the voices, as in voices.json
    POST /v1/tts {text, voice} -> audio/wav (16-bit mono)
"""

import io
import os
import json
import threading
import wave
from pathlib import Path

import numpy as np
import torch
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel, Field
from pocket_tts import TTSModel

HERE = Path(__file__).parent
VOICES = json.loads((HERE / "voices.json").read_text())["voices"]

app = FastAPI(title="Octopilot voice (dev)")
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["GET", "POST"],
    allow_headers=["content-type"],
)

# Most of a reply's wait is here; use the cores (up to 8).
torch.set_num_threads(min(8, os.cpu_count() or 4))
model = TTSModel.load_model()
states = {}
for voice in VOICES:
    path = HERE / "voices" / f"{voice['id']}.safetensors"
    if not path.exists():
        raise SystemExit(f"{path.name} is missing: run build_voices.py first")
    states[voice["id"]] = model.get_state_for_audio_prompt(str(path))
# One synthesis at a time: the model keeps state while it generates.
lock = threading.Lock()


class Speak(BaseModel):
    text: str = Field(min_length=1, max_length=1200)
    voice: str


@app.get("/v1/voices")
def voices():
    return {"voices": [{k: v[k] for k in ("id", "name", "gender", "colors")} for v in VOICES]}


@app.post("/v1/tts")
def tts(body: Speak):
    state = states.get(body.voice)
    if state is None:
        raise HTTPException(404, "unknown voice")
    with lock:
        chunks = [c.detach().cpu().numpy().reshape(-1)
                  for c in model.generate_audio_stream(model_state=state, text_to_generate=body.text)]
    audio = np.concatenate(chunks) if chunks else np.zeros(1, dtype=np.float32)
    pcm = (np.clip(audio, -1, 1) * 32767).astype(np.int16)
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(model.config.mimi.sample_rate)
        w.writeframes(pcm.tobytes())
    return Response(out.getvalue(), media_type="audio/wav")


if __name__ == "__main__":
    import argparse

    args = argparse.ArgumentParser()
    args.add_argument("--host", default="127.0.0.1")
    args.add_argument("--port", type=int, default=8792)
    opts = args.parse_args()
    uvicorn.run(app, host=opts.host, port=opts.port)
