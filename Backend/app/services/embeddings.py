"""Local, open-source embeddings — no commercial embedding API.

Two backends, chosen by EMBEDDINGS_BACKEND:

* ``sentence-transformers`` — the real model (default BAAI/bge-m3, 1024-dim).
  Downloads weights on first use and needs torch; use in real deployments.
* ``fallback`` — a deterministic hash-based embedder producing unit vectors of
  the configured dimension. No model, no torch. Lets the stack boot and tests
  run offline; **not** semantically meaningful, so never ship it to prod.

Both return L2-normalized vectors so cosine similarity == dot product.
"""

from __future__ import annotations

import hashlib
import math

from ..config import Settings, get_settings


class Embedder:
    dim: int

    def embed(self, texts: list[str]) -> list[list[float]]:  # pragma: no cover
        raise NotImplementedError


class FallbackEmbedder(Embedder):
    """Deterministic hash embedding. Dev/test only — not semantic."""

    def __init__(self, dim: int) -> None:
        self.dim = dim

    def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._one(t) for t in texts]

    def _one(self, text: str) -> list[float]:
        vec = [0.0] * self.dim
        for token in text.lower().split():
            h = int.from_bytes(hashlib.sha256(token.encode()).digest()[:8], "big")
            vec[h % self.dim] += 1.0
        norm = math.sqrt(sum(v * v for v in vec)) or 1.0
        return [v / norm for v in vec]


class SentenceTransformerEmbedder(Embedder):
    def __init__(self, model_name: str, dim: int) -> None:
        from sentence_transformers import SentenceTransformer  # lazy import

        self._model = SentenceTransformer(model_name)
        self.dim = dim

    def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        vectors = self._model.encode(
            texts,
            normalize_embeddings=True,
            convert_to_numpy=True,
            batch_size=32,
            show_progress_bar=False,
        )
        return [v.tolist() for v in vectors]


class RemoteEmbedder(Embedder):
    """HTTP client for the dedicated embed worker (one model copy, not in the API)."""

    def __init__(self, url: str, dim: int) -> None:
        self._url = url.rstrip("/")
        self.dim = dim

    def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        import httpx

        resp = httpx.post(
            f"{self._url}/embed", json={"texts": texts}, timeout=180.0
        )
        resp.raise_for_status()
        return resp.json()["vectors"]


def _build(settings: Settings) -> Embedder:
    if settings.embed_service_url.strip():
        return RemoteEmbedder(settings.embed_service_url, settings.embedding_dim)
    if settings.embeddings_backend == "sentence-transformers":
        return SentenceTransformerEmbedder(settings.embeddings_model, settings.embedding_dim)
    return FallbackEmbedder(settings.embedding_dim)


_singleton: Embedder | None = None


def get_embedder(settings: Settings | None = None) -> Embedder:
    """Return the embedder. Passing explicit settings bypasses the cached
    singleton (used in tests); the no-arg call caches one instance."""
    global _singleton
    if settings is not None:
        return _build(settings)
    if _singleton is None:
        _singleton = _build(get_settings())
    return _singleton
