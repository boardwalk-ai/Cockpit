"""Dedicated embedding HTTP server — one process, one BGE-m3 copy.

The FastAPI API and the Go ingest/search workers call this instead of loading
torch in every API worker. The model loads once at startup; `/ready` answers
only after a real test embed, so a broken model shows up at once instead of
as a slow 500 on every request.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .services.embeddings import get_embedder

log = logging.getLogger("embed")
_state: dict = {"ready": False, "error": None, "dim": None}


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        (vec,) = get_embedder().embed(["ready check"])
        _state.update(ready=True, dim=len(vec))
        log.info("embedder ready, dim=%s", len(vec))
    except Exception as exc:  # noqa: BLE001 — reported by /ready
        _state.update(error=f"{type(exc).__name__}: {exc}"[:300])
        log.exception("embedder failed to load")
    yield


app = FastAPI(title="Cockpit embed", lifespan=lifespan)


class EmbedIn(BaseModel):
    texts: list[str]


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.get("/ready")
def ready() -> dict:
    if not _state["ready"]:
        raise HTTPException(503, _state["error"] or "loading")
    return {"ok": True, "dim": _state["dim"]}


@app.post("/embed")
def embed(body: EmbedIn) -> dict:
    if not _state["ready"]:
        # Fail fast: callers fall back instead of waiting on a reload.
        raise HTTPException(503, _state["error"] or "loading")
    return {"vectors": get_embedder().embed(body.texts)}
