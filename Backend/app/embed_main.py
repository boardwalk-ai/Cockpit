"""Dedicated embedding HTTP server — one process, one BGE-m3 copy.

The FastAPI API and the Go ingest/search workers call this instead of loading
torch in every API worker.
"""

from __future__ import annotations

from fastapi import FastAPI
from pydantic import BaseModel

from .services.embeddings import get_embedder

app = FastAPI(title="Cockpit embed")


class EmbedIn(BaseModel):
    texts: list[str]


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.post("/embed")
def embed(body: EmbedIn) -> dict:
    return {"vectors": get_embedder().embed(body.texts)}
