"""Offline unit tests — no DB, no network, fallback embedder."""

from __future__ import annotations

import math

from app.config import Settings
from app.services.embeddings import FallbackEmbedder, get_embedder
from app.services.llm import build_context_block
from app.services.objectstore import ObjectStore
from app.services.rag import chunk_text


def test_fallback_embedder_is_unit_normalized():
    emb = FallbackEmbedder(dim=64)
    (vec,) = emb.embed(["routing protocols and subnet masks"])
    assert len(vec) == 64
    assert math.isclose(math.sqrt(sum(v * v for v in vec)), 1.0, rel_tol=1e-6)


def test_fallback_embedder_is_deterministic():
    emb = FallbackEmbedder(dim=32)
    a = emb.embed(["same text"])
    b = emb.embed(["same text"])
    assert a == b


def test_get_embedder_defaults_to_fallback():
    embedder = get_embedder(Settings(embeddings_backend="fallback", embedding_dim=16))
    assert isinstance(embedder, FallbackEmbedder)
    assert embedder.dim == 16


def test_chunk_text_overlap_and_coverage():
    words = " ".join(str(i) for i in range(100))
    chunks = chunk_text(words, size=30, overlap=10)
    assert chunks, "expected chunks"
    # First chunk holds the first 30 words.
    assert chunks[0].split()[:3] == ["0", "1", "2"]
    # Step is size-overlap=20, so the second chunk starts at word 20.
    assert chunks[1].split()[0] == "20"


def test_chunk_text_empty():
    assert chunk_text("   ", size=10, overlap=2) == []


def test_pdf_text_local_garbage_is_empty():
    from app.services.rag import pdf_text_local

    text, pages = pdf_text_local(b"not a pdf")
    assert text == ""
    assert pages == 0


def test_text_layer_usable_skips_sparse_scans():
    from app.services.rag import _text_layer_usable

    assert _text_layer_usable("x" * 2000, pages=5)
    assert not _text_layer_usable("header", pages=20)
    assert not _text_layer_usable("", pages=1)


def test_context_block_numbering():
    block = build_context_block(["alpha", "beta"])
    assert "[1] alpha" in block
    assert "[2] beta" in block


def test_object_key_is_user_scoped():
    import uuid

    uid = uuid.uuid4()
    did = uuid.uuid4()
    key = ObjectStore.key_for(uid, did, "lecture.pdf")
    assert key == f"{uid}/{did}/lecture.pdf"
    assert key.startswith(str(uid))


def test_generate_stub_topics_are_valid_topic_dtos():
    import asyncio

    from app.dto import TopicDTO
    from app.services.generate import generate_topics

    topics = asyncio.run(
        generate_topics(
            chunks=["Photosynthesis converts light energy into chemical energy."],
            studio_id="s1",
            api_key="",  # no key -> deterministic stub
            model="x",
        )
    )
    assert len(topics) == 1
    payload = topics[0]
    assert payload["studioId"] == "s1"
    assert payload["flashcards"] and payload["quizQuestions"]
    # The stored payload round-trips through the wire DTO.
    dto = TopicDTO.model_validate(payload)
    assert dto.title and dto.flashcards[0].topic_id == payload["id"]


def test_generate_no_chunks_returns_empty():
    import asyncio

    from app.services.generate import generate_topics

    assert asyncio.run(
        generate_topics(chunks=[], studio_id="s", api_key="", model="x")
    ) == []
