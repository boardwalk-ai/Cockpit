"""Puts OctoNotes' on-device caption model into the app: sherpa-onnx's
streaming English zipformer (20M parameters, Apache-2.0), under
apps/cockpit/assets/asr/ (not committed: about 45 MB). Run it before
building the app; without it the app uses the server's live transcript.

    python fetch_asr_model.py
"""

import io
import tarfile
import urllib.request
from pathlib import Path

NAME = "sherpa-onnx-streaming-zipformer-en-20M-2023-02-17"
URL = f"https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/{NAME}.tar.bz2"
OUT = Path(__file__).resolve().parents[2] / "apps" / "cockpit" / "assets" / "asr"

# Archive file (by its ending) -> name the app loads (live_captioner.dart).
WANTED = {
    "encoder-epoch-99-avg-1.int8.onnx": "encoder.int8.onnx",
    "decoder-epoch-99-avg-1.onnx": "decoder.onnx",
    "joiner-epoch-99-avg-1.int8.onnx": "joiner.int8.onnx",
    "tokens.txt": "tokens.txt",
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"downloading {URL}")
    with urllib.request.urlopen(URL) as r:
        data = r.read()
    found = set()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:bz2") as tar:
        for m in tar.getmembers():
            name = Path(m.name).name
            if m.isfile() and name in WANTED:
                (OUT / WANTED[name]).write_bytes(tar.extractfile(m).read())
                found.add(name)
    missing = set(WANTED) - found
    if missing:
        raise SystemExit(f"not in the archive: {sorted(missing)}")
    for f in sorted(OUT.iterdir()):
        print(f"  {f.name}  {f.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
