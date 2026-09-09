"""SSE-first API — every endpoint streams `text/event-stream`.

Reads are served from the seed studios (see app/seed.py) so the Flutter app
renders real data over the wire today; `/ask` streams answer deltas + citations
from the RAG pipeline (or a graceful stub when no LLM key is set). Write
endpoints acknowledge over SSE for a uniform client.
"""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import AsyncIterator

from fastapi import APIRouter, BackgroundTasks, Body, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sse_starlette.sse import EventSourceResponse

from ..config import get_settings
from ..db import CockpitSession, SharedSession, VectorSession
from ..deps import get_current_user_id
from ..dto import AskCitationDTO, MeDTO, ScenarioDTO, StudioDTO, TopicDTO
from ..models.cockpit import (
    Document,
    GeneratedScenario,
    GeneratedTopic,
    IngestJob,
    Studio,
    StudioBuild,
)
from ..seed import seed_studios
from ..services import llm, progress, rag, vectorstore
from ..services.objectstore import get_object_store
from ..sse import done, error, event

router = APIRouter(tags=["sse"])
_STUDIOS = seed_studios()


def _build_progress_pct(status: str, lessons_done: int, lessons_total: int) -> float:
    """Weighted real progress for the live Home build banner.

    extracting reuses lessons_done/total as documents ready/total while ingesting.
    """
    if status == "done":
        return 1.0
    if status == "failed":
        return 0.0
    if status == "queued":
        return 0.02
    if status == "extracting":
        if lessons_total > 0:
            frac = max(0.0, min(1.0, lessons_done / lessons_total))
            return round(0.02 + 0.18 * frac, 4)  # 2% → 20%
        return 0.08
    if status == "generating":
        if lessons_total <= 0:
            return 0.25
        frac = max(0.0, min(1.0, lessons_done / lessons_total))
        return round(0.25 + 0.60 * frac, 4)  # 25% → 85%
    if status == "scenarios":
        return 0.92
    return 0.05


def _build_progress_payload(b: StudioBuild) -> dict:
    return {
        "status": b.status,
        "stage": b.stage,
        "lessonsDone": b.lessons_done,
        "lessonsTotal": b.lessons_total,
        "progressPct": _build_progress_pct(b.status, b.lessons_done, b.lessons_total),
    }

async def _load_topics(
    cockpit: AsyncSession,
    studio_id: uuid.UUID,
    user_id: uuid.UUID | None = None,
) -> list[TopicDTO]:
    """Load the studio's generated Study Objects, overlaying the user's real
    mastery (from topic_progress) onto each topic's stored payload."""
    try:
        rows = await cockpit.execute(
            select(GeneratedTopic)
            .where(GeneratedTopic.studio_id == studio_id)
            .order_by(GeneratedTopic.ordinal)
        )
        mastery = {}
        if user_id is not None:
            try:
                mastery = await progress.mastery_map(
                    cockpit, user_id=user_id, studio_id=studio_id
                )
            except Exception:  # noqa: BLE001 — mastery overlay is best-effort
                mastery = {}
        out: list[TopicDTO] = []
        for r in rows.scalars():
            payload = r.payload
            tid = payload.get("id")
            if tid in mastery:
                payload = {**payload, "mastery": mastery[tid]}
            out.append(TopicDTO.model_validate(payload))
        return out
    except Exception:  # noqa: BLE001
        return []


async def _load_scenarios(
    cockpit: AsyncSession, studio_id: uuid.UUID
) -> list[ScenarioDTO]:
    """Load the studio's generated Scenario-Mode scenarios."""
    try:
        rows = await cockpit.execute(
            select(GeneratedScenario)
            .where(GeneratedScenario.studio_id == studio_id)
            .order_by(GeneratedScenario.ordinal)
        )
        return [ScenarioDTO.model_validate(r.payload) for r in rows.scalars()]
    except Exception:  # noqa: BLE001
        return []


def _db_studio_to_dto(
    row: Studio,
    topics: list[TopicDTO] | None = None,
    scenarios: list[ScenarioDTO] | None = None,
) -> StudioDTO:
    """Map a persisted studio to the wire DTO (topics/scenarios filled after gen)."""
    return StudioDTO(
        id=str(row.id),
        title=row.title,
        subject=row.subject or "",
        created_at=row.created_at,
        updated_at=row.updated_at,
        topics=topics or [],
        scenarios=scenarios or [],
    )


async def _db_studios_for(cockpit: AsyncSession, user_id: uuid.UUID) -> list[StudioDTO]:
    """User's persisted studios (best-effort — empty if the DB is unavailable)."""
    try:
        rows = await cockpit.execute(
            select(Studio).where(Studio.user_id == user_id).order_by(Studio.created_at.desc())
        )
        out = []
        for r in rows.scalars():
            out.append(
                _db_studio_to_dto(
                    r,
                    await _load_topics(cockpit, r.id, user_id),
                    await _load_scenarios(cockpit, r.id),
                )
            )
        return out
    except Exception:  # noqa: BLE001 — DB down in local/seed mode
        return []


@router.get("/me")
async def me(
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    async def gen() -> AsyncIterator[dict]:
        credits = None
        email = None
        if SharedSession is not None:
            from ..models.shared import User

            async with SharedSession() as shared:
                row = await shared.execute(
                    select(User.email, User.octo_credits).where(User.id == user_id)
                )
                found = row.first()
                if found:
                    email, credits = found
        yield event("data", MeDTO(id=str(user_id), email=email, credits=credits))
        yield done()

    return EventSourceResponse(gen())


@router.get("/studios")
async def list_studios(
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    async def gen() -> AsyncIterator[dict]:
        # Owned studios only — seed demos (bio/mbr) used to be appended here and
        # could never be deleted, which made them look like sticky real studios.
        async with CockpitSession() as cockpit:
            studios = await _db_studios_for(cockpit, user_id)
        for studio in studios:
            yield event("item", studio)
        yield done()

    return EventSourceResponse(gen())


@router.post("/studios")
async def create_studio(
    body: dict = Body(...),
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    title = (body.get("title") or "").strip() or "Untitled Studio"
    subject = (body.get("subject") or "").strip() or None

    async def gen() -> AsyncIterator[dict]:
        try:
            async with CockpitSession() as cockpit:
                studio = Studio(user_id=user_id, title=title, subject=subject)
                cockpit.add(studio)
                await cockpit.commit()
                await cockpit.refresh(studio)
                dto = _db_studio_to_dto(studio)
            yield event("data", dto)
            yield done()
        except Exception as exc:  # noqa: BLE001
            yield error(f"Could not create studio: {exc}")

    return EventSourceResponse(gen())


@router.get("/studios/{studio_id}")
async def get_studio(
    studio_id: str,
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    async def gen() -> AsyncIterator[dict]:
        # Persisted studio (owned by the user) first, then the seed demos.
        try:
            sid = uuid.UUID(studio_id)
            async with CockpitSession() as cockpit:
                row = await cockpit.get(Studio, sid)
                owned = row is not None and row.user_id == user_id
                dto = (
                    _db_studio_to_dto(
                        row,
                        await _load_topics(cockpit, sid, user_id),
                        await _load_scenarios(cockpit, sid),
                    )
                    if owned
                    else None
                )
            if dto is not None:
                yield event("data", dto)
                yield done()
                return
        except Exception:  # noqa: BLE001 — non-UUID id (seed) or DB down
            pass
        studio = _STUDIOS.get(studio_id)
        if studio is None:
            yield error(f"Studio {studio_id} not found")
            return
        yield event("data", studio)
        yield done()

    return EventSourceResponse(gen())


@router.delete("/studios/{studio_id}")
async def delete_studio(
    studio_id: str,
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    """Delete an owned studio and all of its data.

    The `studios` row cascades (FK ondelete=CASCADE) to documents, ingest jobs,
    generated topics, and scenarios in the cockpit DB. Vector chunks (separate
    DB, no cross-db FK) and object-storage source files are cleaned explicitly.
    Seed demo studios are read-only and cannot be deleted.
    """

    async def gen() -> AsyncIterator[dict]:
        try:
            sid = uuid.UUID(studio_id)
        except ValueError:
            yield error(f"Studio {studio_id} not found")
            return
        try:
            async with CockpitSession() as cockpit:
                row = await cockpit.get(Studio, sid)
                if row is None or row.user_id != user_id:
                    yield error(f"Studio {studio_id} not found")
                    return
                # Grab object keys before the cascade removes the documents.
                keys = await cockpit.execute(
                    select(Document.object_key).where(Document.studio_id == sid)
                )
                object_keys = [k for (k,) in keys.all()]
                await cockpit.delete(row)  # cascades docs/jobs/topics/scenarios
                await cockpit.commit()

            # Vector chunks (separate DB) — owner-scoped delete, best-effort.
            try:
                async with VectorSession() as vector:
                    await vectorstore.delete_studio_chunks(
                        vector, studio_id=sid, user_id=user_id
                    )
            except Exception:  # noqa: BLE001 — cleanup shouldn't fail the delete
                pass

            # Source files in object storage — best-effort per key.
            store = None
            for key in object_keys:
                try:
                    store = store or get_object_store()
                    store.delete(key)
                except Exception:  # noqa: BLE001
                    pass

            yield event("data", {"id": studio_id, "deleted": True})
            yield done()
        except Exception as exc:  # noqa: BLE001
            yield error(f"Could not delete studio: {exc}")

    return EventSourceResponse(gen())


@router.get("/studios/{studio_id}/build/{job_id}")
async def build_progress(
    studio_id: str,
    job_id: uuid.UUID,
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    """Stream an ingestion job's progress (queued → running → done/failed).

    Uses a short-lived session PER POLL (not one held for the whole stream): a
    long-lived SSE stream that holds a pooled connection leaks it if the client
    disconnects mid-stream. Each poll checks a connection out and back in.
    """

    async def gen() -> AsyncIterator[dict]:
        last = None
        for _ in range(600):  # ~5 min ceiling at 0.5s
            async with CockpitSession() as cockpit:
                job = await cockpit.get(IngestJob, job_id)
                status = None if job is None else job.status
                chunks = None if job is None else job.chunks_written
                owner = None if job is None else job.user_id
                error_msg = None if job is None else job.error
            if job is None or owner != user_id:
                yield error("Job not found")
                return
            if status != last:
                last = status
                yield event("progress", {"status": status, "chunks": chunks})
            if status in ("done", "failed"):
                if status == "failed":
                    yield error(error_msg or "Ingestion failed")
                else:
                    yield done()
                return
            await asyncio.sleep(0.5)
        yield error("Ingestion timed out")

    return EventSourceResponse(gen())


@router.post("/studios/{studio_id}/build")
async def start_studio_build(
    studio_id: str,
    background: BackgroundTasks,
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    """Kick off the studio-level generation pass over ALL uploaded material and
    return its build id. The client streams `/build-status/{buildId}` for live
    progress while the studio fills in — no blocking wait on a spinner."""

    async def gen() -> AsyncIterator[dict]:
        try:
            sid = uuid.UUID(studio_id)
        except ValueError:
            yield error(f"Studio {studio_id} not found")
            return
        try:
            async with CockpitSession() as cockpit:
                row = await cockpit.get(Studio, sid)
                if row is None or row.user_id != user_id:
                    yield error(f"Studio {studio_id} not found")
                    return
                build = StudioBuild(
                    studio_id=sid,
                    user_id=user_id,
                    status="queued",
                    stage="Starting…",
                )
                cockpit.add(build)
                await cockpit.commit()
                await cockpit.refresh(build)
                build_id = build.id
            background.add_task(rag.run_studio_build, build_id=build_id)
            yield event("data", {"buildId": str(build_id), "studioId": studio_id})
            yield done()
        except Exception as exc:  # noqa: BLE001
            yield error(f"Could not start build: {exc}")

    return EventSourceResponse(gen())


@router.get("/studios/{studio_id}/build-status/{build_id}")
async def studio_build_status(
    studio_id: str,
    build_id: uuid.UUID,
    snapshot: bool = Query(False),
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    """A studio build's live progress: stage + lessons done / total.

    `snapshot=true` emits the current state once and ends — the client polls it
    on a short timer so a buffered SSE reader still gets a live banner. Without
    it, the stream stays open until the build finishes."""

    async def snap() -> AsyncIterator[dict]:
        async with CockpitSession() as cockpit:
            b = await cockpit.get(StudioBuild, build_id)
            if b is None or b.user_id != user_id:
                yield error("Build not found")
                return
            yield event("progress", _build_progress_payload(b))
            yield done()

    if snapshot:
        return EventSourceResponse(snap())

    async def gen() -> AsyncIterator[dict]:
        last: tuple | None = None
        for _ in range(1200):  # ~10 min ceiling at 0.5s
            async with CockpitSession() as cockpit:
                b = await cockpit.get(StudioBuild, build_id)
                snap = None if b is None else (
                    b.user_id, b.status, b.stage, b.lessons_done, b.lessons_total, b.error
                )
            if b is None or snap[0] != user_id:
                yield error("Build not found")
                return
            _, status, stage, done_n, total_n, err = snap
            key = (status, stage, done_n, total_n)
            if key != last:
                last = key
                yield event("progress", {
                    "status": status,
                    "stage": stage,
                    "lessonsDone": done_n,
                    "lessonsTotal": total_n,
                    "progressPct": _build_progress_pct(status, done_n, total_n),
                })
            if status == "done":
                yield done()
                return
            if status == "failed":
                yield error(err or "Build failed")
                return
            await asyncio.sleep(0.5)
        yield error("Build timed out")

    return EventSourceResponse(gen())


@router.get("/studios/{studio_id}/topics/{topic_id}")
async def get_topic(studio_id: str, topic_id: str) -> EventSourceResponse:
    async def gen() -> AsyncIterator[dict]:
        studio = _STUDIOS.get(studio_id)
        topic = (
            next((t for t in studio.topics if t.id == topic_id), None)
            if studio
            else None
        )
        if topic is None:
            yield error(f"Topic {topic_id} not found")
            return
        yield event("data", topic)
        yield done()

    return EventSourceResponse(gen())


@router.get("/ask")
async def ask(
    studio_id: str = Query(...),
    q: str = Query(..., min_length=1),
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    settings = get_settings()

    async def gen() -> AsyncIterator[dict]:
        try:
            # Best-effort retrieval (empty until documents are ingested).
            from ..services.vectorstore import retrieve

            try:
                sid = uuid.UUID(studio_id)
            except ValueError:
                sid = uuid.uuid5(uuid.NAMESPACE_DNS, studio_id)

            hits = []
            try:
                hits = await retrieve(
                    None,
                    user_id=user_id,
                    studio_id=sid,
                    query_text=q,
                    top_k=settings.rag_top_k,
                )
            except Exception:  # noqa: BLE001 — retrieval optional in seed mode
                hits = []

            context = llm.build_context_block([h.content for h in hits])
            if SharedSession is not None:
                async with SharedSession() as shared:
                    api_key, model = await llm.resolve_credentials(shared)
            else:
                api_key, model = await llm.resolve_credentials(None)

            async for delta in llm.generate_stream(
                api_key=api_key, model=model, question=q, context=context
            ):
                yield event("delta", {"text": delta})

            if hits:
                yield event(
                    "citations",
                    [
                        AskCitationDTO(
                            chunk_id=str(h.chunk_id),
                            document_id=str(h.document_id),
                            ordinal=h.ordinal,
                            score=round(h.score, 4),
                            snippet=h.content[:280],
                        ).model_dump(by_alias=True)
                        for h in hits[: settings.rag_context_k]
                    ],
                )
            yield event("meta", {"model": model})
            yield done()
        except Exception as exc:  # noqa: BLE001
            yield error(str(exc))

    return EventSourceResponse(gen())


def _ack() -> EventSourceResponse:
    async def gen() -> AsyncIterator[dict]:
        yield event("ok", {"ok": True})
        yield done()

    return EventSourceResponse(gen())


async def _owned_studio_uuid(
    studio_id: str, user_id: uuid.UUID
) -> uuid.UUID | None:
    """Studio UUID if it exists and is owned by the user, else None (seed studios
    have non-UUID ids and are read-only — progress isn't persisted for them)."""
    try:
        sid = uuid.UUID(studio_id)
    except ValueError:
        return None
    async with CockpitSession() as cockpit:
        row = await cockpit.get(Studio, sid)
        return sid if (row is not None and row.user_id == user_id) else None


@router.post("/studios/{studio_id}/topics/{topic_id}/quiz-result")
async def quiz_result(
    studio_id: str,
    topic_id: str,
    correct: bool = Query(...),
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    try:
        sid = await _owned_studio_uuid(studio_id, user_id)
        if sid is not None:
            async with CockpitSession() as cockpit:
                await progress.record_quiz(
                    cockpit, user_id=user_id, studio_id=sid,
                    topic_id=topic_id, correct=correct,
                )
    except Exception:  # noqa: BLE001 — never fail the client's ack
        pass
    return _ack()


@router.post("/studios/{studio_id}/topics/{topic_id}/flashcard-review")
async def flashcard_review(
    studio_id: str,
    topic_id: str,
    quality: float = Query(..., ge=0.0, le=1.0),
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    try:
        sid = await _owned_studio_uuid(studio_id, user_id)
        if sid is not None:
            async with CockpitSession() as cockpit:
                await progress.record_flashcard(
                    cockpit, user_id=user_id, studio_id=sid,
                    topic_id=topic_id, quality=quality,
                )
    except Exception:  # noqa: BLE001
        pass
    return _ack()


@router.post("/studios/{studio_id}/topics/{topic_id}/mark-reviewed")
async def mark_reviewed(
    studio_id: str,
    topic_id: str,
    user_id: uuid.UUID = Depends(get_current_user_id),
) -> EventSourceResponse:
    try:
        sid = await _owned_studio_uuid(studio_id, user_id)
        if sid is not None:
            async with CockpitSession() as cockpit:
                await progress.record_reviewed(
                    cockpit, user_id=user_id, studio_id=sid, topic_id=topic_id,
                )
    except Exception:  # noqa: BLE001
        pass
    return _ack()
