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
    assert dto.summary == ["Built from your uploaded material."]


def test_topic_summary_is_trimmed_and_optional():
    from app.dto import TopicDTO
    from app.services.generate import _shape_topic

    shaped = _shape_topic(
        {"title": "DNS", "summary": [" Names to numbers. ", "", "a", "b", "c"]},
        "s1",
    )
    assert shaped["summary"] == ["Names to numbers.", "a", "b", "c"]
    # A topic stored before summaries existed still loads.
    old = dict(shaped)
    del old["summary"]
    assert TopicDTO.model_validate(old).summary == []


def test_generate_no_chunks_returns_empty():
    import asyncio

    from app.services.generate import generate_topics

    assert asyncio.run(
        generate_topics(chunks=[], studio_id="s", api_key="", model="x")
    ) == []


def test_outline_keeps_only_earlier_lessons_as_prerequisites(monkeypatch):
    import asyncio

    from app.services import generate

    async def fake_generate(**_):
        return (
            '[{"title": "TCP basics", "scope": "a", "buildsOn": ["Routing"]},'
            ' {"title": "Sliding window", "scope": "b", "buildsOn": ["TCP basics"]},'
            ' {"title": "Congestion", "scope": "c",'
            '  "buildsOn": ["TCP basics", "Sliding window", "Made up"]}]'
        )

    monkeypatch.setattr(generate.llm, "generate", fake_generate)
    outline = asyncio.run(
        generate._generate_outline(material="m", api_key="k", model="x")
    )
    assert [o["buildsOn"] for o in outline] == [
        [],
        ["TCP basics"],
        ["TCP basics", "Sliding window"],
    ]


# The same table is checked by the app's port (flashcard_schedule_test.dart).
SCHEDULE_CASES = [
    # (reps, interval, ease, lapses), grade -> (reps, interval, ease, lapses), wait
    ((0, 0.0, 2.5, 0), 0, (0, 0.0, 2.3, 1), ("minutes", 1)),
    ((0, 0.0, 2.5, 0), 1, (0, 0.0, 2.35, 0), ("minutes", 10)),
    ((0, 0.0, 2.5, 0), 2, (1, 1.0, 2.5, 0), ("days", 1)),
    ((0, 0.0, 2.5, 0), 3, (1, 4.0, 2.65, 0), ("days", 4)),
    ((1, 1.0, 2.5, 0), 2, (2, 3.0, 2.5, 0), ("days", 3)),
    ((2, 3.0, 2.5, 0), 2, (3, 7.5, 2.5, 0), ("days", 7.5)),
    ((2, 3.0, 2.5, 0), 1, (3, 3.6, 2.35, 0), ("days", 3.6)),
    ((2, 3.0, 2.5, 0), 3, (3, 9.75, 2.65, 0), ("days", 9.75)),
    ((3, 7.5, 1.35, 1), 0, (0, 0.0, 1.3, 2), ("minutes", 1)),
    ((3, 7.5, 2.95, 0), 3, (4, 28.7625, 3.0, 0), ("days", 28.7625)),
]


def test_schedule_follows_the_table():
    from datetime import timedelta

    import pytest

    from app.services.schedule import CardState, next_state

    for before, grade, after, (unit, n) in SCHEDULE_CASES:
        state, wait = next_state(CardState(*before), grade)
        assert state.reps == after[0], (before, grade)
        assert state.interval_days == pytest.approx(after[1]), (before, grade)
        assert state.ease == pytest.approx(after[2]), (before, grade)
        assert state.lapses == after[3], (before, grade)
        assert wait == timedelta(**{unit: n}), (before, grade)


def test_outline_keeps_related_titles_that_exist(monkeypatch):
    import asyncio

    from app.services import generate

    async def fake_generate(**_):
        return (
            '[{"title": "A", "scope": "", "relatesTo": ["C", "Nope", "A"]},'
            ' {"title": "B", "scope": "", "buildsOn": ["A"], "relatesTo": ["A"]},'
            ' {"title": "C", "scope": "", "relatesTo": ["A", "A"]}]'
        )

    monkeypatch.setattr(generate.llm, "generate", fake_generate)
    out = asyncio.run(generate._generate_outline(material="m", api_key="k", model="x"))
    assert [o["relatesTo"] for o in out] == [["C"], [], ["A"]]


def test_connections_for_old_studios_are_cleaned():
    from app.services.generate import _clean_connections

    titles = ["A", "B", "C"]
    raw = {
        "A": {"buildsOn": ["B"], "relatesTo": ["C", "Z"]},
        "B": {"buildsOn": ["A", "A"], "relatesTo": ["A", "C"]},
        "C": {"buildsOn": ["A", "B", "C"], "relatesTo": []},
        "Q": {"buildsOn": ["A"]},
    }
    assert _clean_connections(raw, titles) == {
        "A": {"buildsOn": [], "relatesTo": ["C"]},
        "B": {"buildsOn": ["A"], "relatesTo": ["C"]},
        "C": {"buildsOn": ["A", "B"], "relatesTo": []},
    }


def test_related_ids_go_both_ways():
    from app.routers.stream import _related_ids

    payloads = [
        {"id": "a", "title": "DNS", "relatesTo": ["TCP basics"]},
        {"id": "b", "title": "TCP basics"},
        {"id": "c", "title": "Routing", "relatesTo": ["dns", "Missing"]},
    ]
    assert _related_ids(payloads) == {
        "a": ["b", "c"],
        "b": ["a"],
        "c": ["a"],
    }


def test_concept_maps_keep_real_names_and_links():
    from app.dto import TopicDTO
    from app.services.generate import _shape_topic, shape_concepts

    raw = {
        "title": "Congestion control",
        "concepts": [
            {"name": "Packet loss", "meaning": "A dropped packet.", "example": "x"},
            {"name": "Duplicate ACK", "meaning": "A repeated ack."},
            {"name": "packet loss", "meaning": "dup"},
            {"name": "Congestion window"},
        ],
        "links": [
            {"from": "Packet loss", "label": "triggers", "to": "Duplicate ACK"},
            {"from": "duplicate ack", "label": "halves", "to": "Congestion window"},
            {"from": "Packet loss", "label": "triggers", "to": "Duplicate ACK"},
            {"from": "Packet loss", "label": "is caused by", "to": "Routing"},
            {"from": "Ghost", "label": "x", "to": "Packet loss"},
            {"from": "Packet loss", "label": "", "to": "Duplicate ACK"},
        ],
        "_otherTitles": ["Routing"],
    }
    out = shape_concepts(raw, "t1")
    assert [c["name"] for c in out["concepts"]] == [
        "Packet loss", "Duplicate ACK", "Congestion window",
    ]
    ids = {c["name"]: c["id"] for c in out["concepts"]}
    assert out["conceptLinks"] == [
        {"from": ids["Packet loss"], "label": "triggers", "to": ids["Duplicate ACK"]},
        {"from": ids["Duplicate ACK"], "label": "halves", "to": ids["Congestion window"]},
        {"from": ids["Packet loss"], "label": "is caused by", "toTopic": "Routing"},
    ]
    # Through the whole topic and the wire DTO, camelCase and "from" intact.
    payload = _shape_topic(raw, "s1")
    dto = TopicDTO.model_validate(payload)
    wire = dto.model_dump(by_alias=True)
    assert wire["conceptLinks"][0]["from"].endswith("_c0")
    assert wire["conceptLinks"][2]["toTopic"] == "Routing"
    assert "_otherTitles" not in payload


def test_ask_history_is_trimmed_and_safe():
    import json as _json

    from app.routers.stream import parse_history, search_text

    raw = _json.dumps(
        [{"q": f"q{i}", "a": f"a{i}"} for i in range(5)]
        + [{"q": "no answer"}, "junk", {"q": "x" * 5000, "a": "y"}]
    )
    turns = parse_history(raw)
    assert [q for q, _ in turns] == ["q3", "q4", "x" * 1200]
    assert parse_history("not json") == []
    assert parse_history('{"q": 1}') == []
    assert parse_history(None) == []

    # A short follow-up borrows the last question; a topic leads.
    assert search_text("why?", [("What is NAT?", "…")], "NAT") == "NAT What is NAT? why?"
    long_q = "how does a router choose the next hop for a packet today"
    assert search_text(long_q, [("What is NAT?", "…")], None) == long_q


def test_ask_messages_carry_history_and_topic():
    from app.services.llm import ask_messages

    msgs = ask_messages(
        question="why?", context="[1] x", history=[("What is NAT?", "It maps.")],
        focus="NAT",
    )
    assert [m["role"] for m in msgs] == ["system", "user", "assistant", "user"]
    assert '"NAT"' in msgs[0]["content"]
    assert msgs[-1]["content"].endswith("Question: why?")
    assert "[1] x" in msgs[-1]["content"]


def test_activity_buckets_by_local_day():
    from datetime import UTC, datetime

    from app.services.activity import CARD, QUIZ, Event, bucket

    now = datetime(2026, 10, 7, 20, 0, tzinfo=UTC)  # 02:30 on the 8th in Yangon
    events = [
        Event(datetime(2026, 10, 7, 19, 0, tzinfo=UTC), CARD, True),  # 8th local
        Event(datetime(2026, 10, 7, 10, 0, tzinfo=UTC), QUIZ, True),  # 7th
        Event(datetime(2026, 10, 7, 11, 0, tzinfo=UTC), QUIZ, False),  # 7th
        Event(datetime(2026, 9, 1, 11, 0, tzinfo=UTC), CARD, True),  # too old
    ]
    rows = bucket(events, days=3, tz_minutes=390, now=now)
    assert [r["date"] for r in rows] == ["2026-10-06", "2026-10-07", "2026-10-08"]
    assert rows[1] == {"date": "2026-10-07", "cards": 0, "quiz": 2, "quizRight": 1}
    assert rows[2]["cards"] == 1
    assert rows[0] == {"date": "2026-10-06", "cards": 0, "quiz": 0, "quizRight": 0}


def test_rebuild_keeps_ids_of_returning_topics_and_cards():
    from app.services.generate import carry_ids, keep_map

    old = [
        {
            "id": "gen_old",
            "title": "Congestion  Control",
            "flashcards": [{"id": "fc_a", "front": "What halves?"}],
        },
        {"id": "gen_gone", "title": "Old topic", "flashcards": []},
    ]
    keep = keep_map(old)
    new = {
        "id": "gen_new",
        "title": "congestion control",
        "flashcards": [
            {"id": "fc_x", "topicId": "gen_new", "front": "what halves?"},
            {"id": "fc_y", "topicId": "gen_new", "front": "Brand new"},
        ],
        "quizQuestions": [{"id": "q1", "topicId": "gen_new"}],
    }
    out = carry_ids(new, keep)
    assert out["id"] == "gen_old"
    assert [c["id"] for c in out["flashcards"]] == ["fc_a", "fc_y"]
    assert {c["topicId"] for c in out["flashcards"]} == {"gen_old"}
    assert out["quizQuestions"][0]["topicId"] == "gen_old"
    other = carry_ids({"id": "gen_z", "title": "Fresh"}, keep)
    assert other["id"] == "gen_z"
