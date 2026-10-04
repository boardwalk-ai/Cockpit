"""Builds the on-device voices: each voice's conditioning embedding for the
Pocket TTS ONNX bundle (soniqo/Pocket-TTS-100M-ONNX-INT8).

That bundle is the english_2026-01 checkpoint, so the embeddings are made
with it too: the first 10 seconds of the voice's recording, encoded by Mimi
and projected (the same as the bundle's own `alba`; checked to a cosine of
0.99999). Each is saved as raw little-endian float32, [125, 1024].

Needs the gated kyutai/pocket-tts weights (`hf auth login`).

    python build_onnx_voices.py    # -> onnx/voices/<id>.f32
"""

import json
from pathlib import Path

import numpy as np
import torch
from huggingface_hub import hf_hub_download
from pocket_tts.data.audio import audio_read
from pocket_tts.data.audio_utils import convert_audio
from pocket_tts.models.tts_model import TTSModel

HERE = Path(__file__).parent
OUT = HERE / "onnx" / "voices"


def main() -> None:
    voices = json.loads((HERE / "voices.json").read_text())["voices"]
    OUT.mkdir(parents=True, exist_ok=True)
    model = TTSModel.load_model(language="english_2026-01")
    if not model.has_voice_cloning:
        raise SystemExit("No access to the cloning weights: run `hf auth login`.")
    rate = model.config.mimi.sample_rate
    for voice in voices:
        audio, sr = audio_read(hf_hub_download("kyutai/tts-voices", voice["source"]))
        audio = convert_audio(audio, sr, rate, 1)[..., : 10 * rate]
        with torch.no_grad():
            embedding = model._encode_audio(audio.unsqueeze(0)).float().numpy()[0]
        embedding.astype("<f4").tofile(OUT / f"{voice['id']}.f32")
        print(f"{voice['name']}: {embedding.shape}")


if __name__ == "__main__":
    main()
