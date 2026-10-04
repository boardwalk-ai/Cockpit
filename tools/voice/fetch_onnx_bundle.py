"""Puts the on-device voice model into the app: the Pocket TTS ONNX bundle
(soniqo/Pocket-TTS-100M-ONNX-INT8, CC BY 4.0) and the voices made by
build_onnx_voices.py, under apps/cockpit/assets/tts/ (not committed: about
120 MB). Run it before building the app.

    python fetch_onnx_bundle.py
"""

import shutil
from pathlib import Path

import onnx
from huggingface_hub import hf_hub_download

REPO = "soniqo/Pocket-TTS-100M-ONNX-INT8"
REVISION = "v1.0.0"
FILES = [
    "text_conditioner.onnx",
    "lm_main.int8.onnx",
    "lm_flow.int8.onnx",
    "decoder.int8.onnx",
    "vocab.json",
    "token_scores.json",
    "LICENSE",
]

# The ONNX Runtime in the Flutter plugin (1.15) reads IR versions up to 9.
# The graphs use opset 14 only, so an IR 10 header can say 9.
MAX_IR = 9

# The LM's attention cache is fixed at 1000 positions in the export, and
# every step copies all of it (about 50 MB). Naming that axis lets the app
# size the cache to the sentence; the graph reads the length from the
# shape, so the result is the same (checked against 1000) and faster.
CACHE = 1000


def dynamic_cache(model: onnx.ModelProto) -> bool:
    changed = False
    for value in [*model.graph.input, *model.graph.output, *model.graph.value_info]:
        dims = value.type.tensor_type.shape.dim
        if len(dims) == 5 and dims[2].dim_value == CACHE:
            dims[2].ClearField("dim_value")
            dims[2].dim_param = "cache"
            changed = True
    return changed

HERE = Path(__file__).parent
ASSETS = HERE.parents[1] / "apps" / "cockpit" / "assets" / "tts"


def main() -> None:
    (ASSETS / "voices").mkdir(parents=True, exist_ok=True)
    for name in FILES:
        try:
            path = hf_hub_download(REPO, name, revision=REVISION)
        except Exception:
            path = hf_hub_download(REPO, name)
        shutil.copy(path, ASSETS / name)
        if name.endswith(".onnx"):
            model = onnx.load(str(ASSETS / name))
            changed = dynamic_cache(model) if name.startswith("lm_main") else False
            if model.ir_version > MAX_IR:
                model.ir_version = MAX_IR
                changed = True
            if changed:
                onnx.save(model, str(ASSETS / name))
        print(name)
    voices = sorted((HERE / "onnx" / "voices").glob("*.f32"))
    if not voices:
        raise SystemExit("No voices: run build_onnx_voices.py first.")
    for voice in voices:
        shutil.copy(voice, ASSETS / "voices" / voice.name)
        print("voices/" + voice.name)


if __name__ == "__main__":
    main()
