"""Builds Octopilot's voice files from voices.json.

Each voice is cloned once from its source recording and saved as a voice
state (`voices/<id>.safetensors`, ~6 MB). The app's model then speaks in that
voice without the recording and without the cloning weights.

Needs the gated `kyutai/pocket-tts` weights (accept the terms on Hugging Face
and `hf auth login` first).

    python build_voices.py
"""

import json
from pathlib import Path

from huggingface_hub import hf_hub_download
from pocket_tts import TTSModel, export_model_state

HERE = Path(__file__).parent
OUT = HERE / "voices"


def main() -> None:
    voices = json.loads((HERE / "voices.json").read_text())["voices"]
    OUT.mkdir(exist_ok=True)
    model = TTSModel.load_model()
    if not model.has_voice_cloning:
        raise SystemExit("No access to the cloning weights: accept the terms on "
                         "huggingface.co/kyutai/pocket-tts and run `hf auth login`.")
    for voice in voices:
        recording = hf_hub_download("kyutai/tts-voices", voice["source"])
        state = model.get_state_for_audio_prompt(recording, truncate=True)
        export_model_state(state, OUT / f"{voice['id']}.safetensors")
        print(f"{voice['name']}: {voice['source']}")


if __name__ == "__main__":
    main()
