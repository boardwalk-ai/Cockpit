import io
import threading

from fastapi import FastAPI, HTTPException, Request
from PIL import Image
from pix2text import LatexOCR

ocr = LatexOCR()
lock = threading.Lock()  # one formula at a time: it's CPU-bound
app = FastAPI()


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/formula")
async def formula(req: Request):
    body = await req.body()
    if not body or len(body) > 5_000_000:
        raise HTTPException(400, "send a PNG up to 5 MB")
    try:
        img = Image.open(io.BytesIO(body)).convert("RGB")
    except Exception:
        raise HTTPException(400, "not an image")
    with lock:
        out = ocr.recognize(img)
    return {"latex": out["text"].strip(), "score": float(out["score"])}
