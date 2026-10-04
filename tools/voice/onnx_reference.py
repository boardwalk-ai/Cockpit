"""A plain reference of the on-device synthesis, step for step as the app
does it (apps/cockpit/lib/voice/pocket_tts.dart): tokenizer, voice and text
conditioning, then one 80 ms frame at a time (LM, four flow steps, Mimi
decoder) until the end-of-speech score crosses the threshold.

    python onnx_reference.py <bundle dir> <voice.f32> "Some text." out.wav
"""

import json
import sys
import time
import wave
from pathlib import Path

import numpy as np
import onnxruntime as ort

FLOW_STEPS = 4
EOS_THRESHOLD = -4.0
TEMPERATURE = 0.7
MAX_FRAMES = 500


def prepare(text: str) -> tuple[str, int]:
    """Pocket TTS's own text preparation (text_chunking.prepare_text_prompt)."""
    text = " ".join(text.replace("\n", " ").split())
    after_eos = 3 if len(text.split()) <= 4 else 1
    if text and not text[0].isupper():
        text = text[0].upper() + text[1:]
    closers = "\"'”’)]»"
    core = text.rstrip(closers + " ")
    if core and core[-1] not in ".!?…":
        if core[-1] in ",;:-–—":
            text = core.rstrip(",;:-–— ") + "." + text[len(core):].strip()
        else:
            text += "."
    if len(text.split()) < 5:
        text = " " * 8 + text
    return text, after_eos


class Tokenizer:
    """SentencePiece unigram over vocab.json and token_scores.json."""

    def __init__(self, bundle: Path):
        vocab = json.loads((bundle / "vocab.json").read_text(encoding="utf-8"))
        scores = json.loads((bundle / "token_scores.json").read_text(encoding="utf-8"))
        self.pieces = {k.encode("utf-8"): (v, scores[k]) for k, v in vocab.items()}
        self.longest = max(len(k) for k in self.pieces)
        self.byte_ids = {}
        for b in range(256):
            name = f"<0x{b:02X}>"
            if name in vocab:
                self.byte_ids[b] = (vocab[name], scores[name])

    def encode(self, text: str) -> list[int]:
        # SentencePiece always adds a word marker in front ("dummy prefix").
        data = ("▁" + text.replace(" ", "▁")).encode("utf-8")
        n = len(data)
        best = [-1e30] * (n + 1)
        back = [-1] * (n + 1)
        ids = [-1] * (n + 1)
        best[n] = 0.0
        for start in range(n - 1, -1, -1):
            for end in range(start + 1, min(n, start + self.longest) + 1):
                hit = self.pieces.get(data[start:end])
                if hit and hit[1] + best[end] > best[start]:
                    best[start] = hit[1] + best[end]
                    back[start], ids[start] = end, hit[0]
            if back[start] < 0:
                fallback = self.byte_ids.get(data[start])
                if fallback:
                    best[start] = fallback[1] + best[start + 1]
                    ids[start] = fallback[0]
                back[start] = start + 1
        out, at = [], 0
        while at < n:
            out.append(ids[at])
            at = back[at]
        return out


def zeros_state(session: ort.InferenceSession, first: int) -> list[np.ndarray]:
    kinds = {"tensor(float)": np.float32, "tensor(int64)": np.int64, "tensor(bool)": np.bool_}
    return [
        np.zeros([d if isinstance(d, int) else 1 for d in i.shape], kinds[i.type])
        for i in session.get_inputs()[first:]
    ]


def synthesize(bundle: Path, voice: np.ndarray, text: str, seed: int = 1) -> np.ndarray:
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 2
    load = lambda f: ort.InferenceSession(str(bundle / f), opts, providers=["CPUExecutionProvider"])
    cond, lm, flow, dec = (load(f) for f in (
        "text_conditioner.onnx", "lm_main.int8.onnx", "lm_flow.int8.onnx", "decoder.int8.onnx"))
    lm_in = [i.name for i in lm.get_inputs()]
    dec_in = [i.name for i in dec.get_inputs()]

    text, after_eos = prepare(text)
    ids = np.array([Tokenizer(bundle).encode(text)], np.int64)
    text_emb = cond.run(None, {"token_ids": ids})[0]

    state = zeros_state(lm, 2)

    def run_lm(sequence, embedding):
        nonlocal state
        out = lm.run(None, dict(zip(lm_in, [sequence, embedding, *state])))
        state = out[2:]
        return out[0], out[1]

    empty_seq = np.zeros((1, 0, 32), np.float32)
    run_lm(empty_seq, voice[None].astype(np.float32))
    run_lm(empty_seq, text_emb)

    dec_state = zeros_state(dec, 1)
    empty_text = np.zeros((1, 0, 1024), np.float32)
    current = np.full((1, 1, 32), np.nan, np.float32)
    rng = np.random.default_rng(seed)
    frames, eos_at = [], -1
    limit = min(MAX_FRAMES, 1000 - voice.shape[0] - ids.shape[1])
    for frame in range(limit):
        conditioning, eos = run_lm(current, empty_text)
        if eos_at < 0 and float(eos.reshape(-1)[0]) > EOS_THRESHOLD:
            eos_at = frame
        if eos_at >= 0 and frame >= eos_at + after_eos:
            break
        latent = rng.normal(0, np.sqrt(TEMPERATURE), (1, 32)).astype(np.float32)
        for step in range(FLOW_STEPS):
            s = np.array([[step / FLOW_STEPS]], np.float32)
            t = np.array([[(step + 1) / FLOW_STEPS]], np.float32)
            latent += flow.run(None, {"c": conditioning, "s": s, "t": t, "x": latent})[0] / FLOW_STEPS
        current = latent[None]
        out = dec.run(None, dict(zip(dec_in, [current, *dec_state])))
        dec_state = out[1:]
        frames.append(out[0].reshape(-1))
    return np.concatenate(frames) if frames else np.zeros(0, np.float32)


def main() -> None:
    bundle, voice_file, text, out = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
    voice = np.fromfile(voice_file, "<f4").reshape(-1, 1024)
    started = time.time()
    audio = synthesize(bundle, voice, text)
    took = time.time() - started
    pcm = (np.clip(audio, -1, 1) * 32767).astype(np.int16)
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(24000)
        w.writeframes(pcm.tobytes())
    print(f"{len(audio) / 24000:.1f}s of audio in {took:.1f}s")


if __name__ == "__main__":
    main()
