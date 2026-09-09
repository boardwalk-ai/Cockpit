"""RAG orchestration: text extraction, chunking, ingestion, and answering.

Ingestion pipeline (async, kicked off after upload):
    object storage -> extract text -> chunk -> store (fast) -> embed (background)

Answering pipeline:
    embed question -> hybrid search (tenant-scoped) -> build context -> OpenRouter
"""

from __future__ import annotations

import asyncio
import base64
import io
import logging
import time
import uuid

import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..models.cockpit import Document, IngestJob
from . import generate, llm, vectorstore
from .embeddings import FallbackEmbedder, get_embedder
from .objectstore import get_object_store

logger = logging.getLogger("cockpit.ingest")


# ---------------------------------------------------------------------------
# Text extraction
# ---------------------------------------------------------------------------
_HIRARA_TIMEOUT = 120.0
_OFFICE_EXT = (".docx", ".doc", ".pptx", ".ppt", ".xlsx", ".xls")
_IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff", ".bmp", ".gif")
_AV_EXT = (".mp3", ".wav", ".m4a", ".flac", ".ogg", ".mp4", ".mov", ".mkv", ".webm")


async def _hirara_call(tool: str, arguments: dict) -> dict:
    """Invoke one Hirara hub tool over its `POST /call` gateway."""
    settings = get_settings()
    headers = {"Content-Type": "application/json"}
    if settings.hirara_hub_token:
        headers["Authorization"] = f"Bearer {settings.hirara_hub_token}"
    async with httpx.AsyncClient(timeout=_HIRARA_TIMEOUT) as client:
        resp = await client.post(
            f"{settings.hirara_hub_url}/call",
            json={"name": tool, "arguments": arguments},
            headers=headers,
        )
        resp.raise_for_status()
        return resp.json()


_MIN_PDF_TEXT_CHARS = 20
_MIN_CHARS_PER_PAGE = 40  # below this, treat as scanned / image-only


def pdf_text_local(data: bytes) -> tuple[str, int]:
    """Return (extracted text, page count) from the PDF's embedded text layer."""
    from pypdf import PdfReader

    try:
        reader = PdfReader(io.BytesIO(data))
    except Exception:  # noqa: BLE001
        return "", 0
    parts: list[str] = []
    for page in reader.pages:
        try:
            parts.append(page.extract_text() or "")
        except Exception:  # noqa: BLE001
            continue
    return "\n\n".join(parts).strip(), len(reader.pages)


def _text_layer_usable(text: str, pages: int) -> bool:
    """True when the PDF already has a real text layer — skip OCR.

    A scanned PDF often still has a few header/footer glyphs; require both a
    floor of characters and a minimum density per page.
    """
    if len(text) < _MIN_PDF_TEXT_CHARS:
        return False
    n = max(pages, 1)
    return (len(text) / n) >= _MIN_CHARS_PER_PAGE


async def extract_text(filename: str, mime: str, data: bytes) -> str:
    """Extract plain text from an uploaded file.

    Text/markdown decode directly. PDFs use local pypdf first (text layer).
    Whole-file OCR runs only when that layer is missing or too sparse to be a
    real document (scanned / image-only PDFs). Digital PDFs never hit OCR.
    """
    name = filename.lower()
    mime = mime or ""

    # Fast path: plain text / markdown.
    if mime.startswith("text/") or name.endswith((".txt", ".md", ".markdown")):
        return data.decode("utf-8", errors="replace")

    # PDF — local text layer first (seconds). OCR only if it's a scan.
    if mime == "application/pdf" or name.endswith(".pdf"):
        local, pages = await asyncio.to_thread(pdf_text_local, data)
        if _text_layer_usable(local, pages):
            logger.info(
                "PDF extract local (skip OCR): %s (%s chars, %s pages)",
                filename, len(local), pages,
            )
            return local
        logger.info(
            "PDF %s has no usable text layer (%s chars / %s pages) — OCR",
            filename, len(local), pages,
        )
        b64 = base64.b64encode(data).decode()
        res = await _hirara_call("pdf_read", {"pdf_base64": b64})
        text = (res.get("text") or "").strip()
        if _text_layer_usable(text, pages):
            logger.info("PDF extract hirara pdf_read: %s (%s chars)", filename, len(text))
            return text
        if not get_settings().ingest_pdf_ocr:
            logger.warning("PDF %s needs OCR but INGEST_PDF_OCR=false", filename)
            return text or local
        ocr = await _hirara_call(
            "ocr_read", {"file_base64": b64, "languages": ["en"]}
        )
        return (ocr.get("text") or ocr.get("markdown") or text or local).strip()

    b64 = base64.b64encode(data).decode()

    # Office documents → Markdown.
    if name.endswith(_OFFICE_EXT) or "officedocument" in mime or "msword" in mime \
            or "ms-powerpoint" in mime or "ms-excel" in mime:
        res = await _hirara_call(
            "office_read", {"file_base64": b64, "filename": filename}
        )
        return (res.get("markdown") or res.get("text") or "").strip()

    # Images → OCR.
    if mime.startswith("image/") or name.endswith(_IMAGE_EXT):
        res = await _hirara_call(
            "ocr_read", {"file_base64": b64, "languages": ["en"]}
        )
        return (res.get("text") or res.get("markdown") or "").strip()

    # Audio / video — STT service not deployed yet (Hirara Phase 2).
    if mime.startswith(("audio/", "video/")) or name.endswith(_AV_EXT):
        raise NotImplementedError(
            "Audio/video transcription (speech-to-text) is not enabled yet."
        )

    raise NotImplementedError(f"No text extractor for mime={mime!r} ({filename}).")


# ---------------------------------------------------------------------------
# Chunking (word-approx tokens with overlap)
# ---------------------------------------------------------------------------
def chunk_text(text: str, *, size: int, overlap: int) -> list[str]:
    words = text.split()
    if not words:
        return []
    step = max(size - overlap, 1)
    chunks: list[str] = []
    for start in range(0, len(words), step):
        window = words[start : start + size]
        if window:
            chunks.append(" ".join(window))
        if start + size >= len(words):
            break
    return chunks


# ---------------------------------------------------------------------------
# Ingestion
# ---------------------------------------------------------------------------
async def run_ingest(
    *,
    cockpit: AsyncSession,
    vector: AsyncSession,
    job_id: uuid.UUID,
    document: Document,
) -> None:
    settings = get_settings()
    await _set_job(cockpit, job_id, status="running")
    t0 = time.monotonic()
    try:
        raw = await asyncio.to_thread(get_object_store().get, document.object_key)
        t_get = time.monotonic()
        text = await extract_text(document.filename, document.mime, raw)
        t_extract = time.monotonic()
        pieces = chunk_text(
            text, size=settings.rag_chunk_tokens, overlap=settings.rag_chunk_overlap
        )
        # Cheap placeholder vectors so we can mark the document ready (and let
        # studio build start) without waiting on BGE-m3 CPU inference.
        dim = settings.embedding_dim
        placeholders = FallbackEmbedder(dim).embed(pieces) if pieces else []

        rows = [
            {
                "id": uuid.uuid4(),
                "document_id": document.id,
                "studio_id": document.studio_id,
                "user_id": document.user_id,
                "ordinal": i,
                "content": piece,
                "embedding": placeholders[i],
            }
            for i, piece in enumerate(pieces)
        ]
        written = await vectorstore.insert_chunks(vector, rows=rows)

        await _set_job(cockpit, job_id, status="done", chunks_written=written)
        await cockpit.execute(
            update(Document).where(Document.id == document.id).values(status="ready")
        )
        await cockpit.commit()
        logger.info(
            "ingest ready %s extract=%.1fs store=%.1fs chunks=%s",
            document.filename,
            t_extract - t_get,
            time.monotonic() - t0,
            written,
        )

        embedder = get_embedder()
        if pieces and not isinstance(embedder, FallbackEmbedder):
            try:
                real = await asyncio.to_thread(embedder.embed, pieces)
                await vectorstore.update_embeddings(
                    vector,
                    rows=[
                        {"id": rows[i]["id"], "embedding": real[i]}
                        for i in range(len(rows))
                    ],
                )
                logger.info(
                    "ingest embeddings %s extra=%.1fs",
                    document.filename,
                    time.monotonic() - t_extract,
                )
            except Exception:  # noqa: BLE001 — text is already ready for generate
                logger.exception("background embed failed for %s", document.filename)
    except Exception as exc:  # noqa: BLE001 — record the failure on the job
        await _set_job(cockpit, job_id, status="failed", error=str(exc))
        await cockpit.execute(
            update(Document).where(Document.id == document.id).values(status="failed")
        )
        await cockpit.commit()


async def _set_job(session: AsyncSession, job_id: uuid.UUID, **values) -> None:
    await session.execute(update(IngestJob).where(IngestJob.id == job_id).values(**values))
    await session.commit()


# ---------------------------------------------------------------------------
# Studio-level build — ONE generation pass over all ingested material
# ---------------------------------------------------------------------------
async def _wait_for_documents_ready(
    *,
    studio_id: uuid.UUID,
    set_progress,
    timeout_s: float = 600.0,
    poll_s: float = 1.0,
) -> bool:
    """Block until every studio document is ready or failed; stream ingest stage."""
    import asyncio
    import time

    from ..db import CockpitSession
    from ..models.cockpit import Document

    deadline = time.monotonic() + timeout_s
    while True:
        async with CockpitSession() as s:
            rows = (
                await s.execute(select(Document).where(Document.studio_id == studio_id))
            ).scalars().all()
        if not rows:
            await set_progress(status="failed", error="No documents uploaded.")
            return False

        ready = [d for d in rows if d.status == "ready"]
        failed = [d for d in rows if d.status == "failed"]
        pending = [d for d in rows if d.status not in ("ready", "failed")]
        total = len(rows)
        done_n = len(ready) + len(failed)

        current = pending[0].filename if pending else (ready[-1].filename if ready else "")
        if len(current) > 64:
            current = current[:61] + "…"
        stage = (
            f"Ingesting document… {len(ready)} of {total}"
            + (f": {current}" if pending and current else "")
        )
        # Temporarily reuse lesson counters so progressPct can track ingest.
        await set_progress(
            status="extracting",
            stage=stage[:160],
            lessons_done=len(ready),
            lessons_total=total,
        )

        if not pending:
            if not ready:
                err = failed[0].filename if failed else "ingest"
                await set_progress(
                    status="failed",
                    error=f"Documents failed to ingest ({err}).",
                )
                return False
            return True

        if time.monotonic() >= deadline:
            await set_progress(status="failed", error="Timed out ingesting documents.")
            return False
        await asyncio.sleep(poll_s)


async def run_studio_build(*, build_id: uuid.UUID) -> None:
    """Generate the studio's Study Objects from the COMBINED material of every
    uploaded file, persisting lessons incrementally so the client fills in live.

    Runs in its own DB sessions (background task). Progress + counts are tracked
    on the StudioBuild row, which the client streams for a live progress banner.
    """
    from ..db import CockpitSession, SharedSession, VectorSession
    from ..models.cockpit import Document, StudioBuild

    settings = get_settings()

    async def _set(**values) -> None:
        async with CockpitSession() as s:
            await s.execute(
                update(StudioBuild).where(StudioBuild.id == build_id).values(**values)
            )
            await s.commit()

    async with CockpitSession() as cockpit:
        build = await cockpit.get(StudioBuild, build_id)
        if build is None:
            return
        studio_id = build.studio_id
        user_id = build.user_id
        # Filename map for citations (document_id -> filename).
        docs = await cockpit.execute(
            select(Document.id, Document.filename).where(Document.studio_id == studio_id)
        )
        filename_map = {str(i): n for i, n in docs.all()}

    try:
        # Upload page hands off immediately; wait here so the Home banner can
        # show "Ingesting document…" instead of racing an empty vector store.
        if not await _wait_for_documents_ready(studio_id=studio_id, set_progress=_set):
            return

        await _set(
            status="extracting",
            stage="Reading your materials…",
            lessons_done=0,
            lessons_total=0,
        )
        async with VectorSession() as vector:
            pieces = await vectorstore.fetch_studio_chunks(
                vector, studio_id=studio_id, user_id=user_id
            )
        if not pieces:
            await _set(status="failed", error="No material was ingested.")
            return

        api_key = settings.openrouter_api_key
        model = settings.openrouter_model
        if SharedSession is not None:
            async with SharedSession() as shared:
                api_key, primary = await llm.resolve_credentials(shared)
                model = await llm.get_setting(shared, "secondary_model", primary)

        # Fresh slate, then live-fill as each lesson lands.
        async with CockpitSession() as s:
            await generate.clear_topics(s, studio_id=studio_id)
        await _set(status="generating", stage="Building studio…")

        async def on_outline(total: int) -> None:
            await _set(
                lessons_total=total,
                stage=f"Getting lessons… 0 of {total}",
            )

        async def on_topic(ordinal: int, topic: dict) -> None:
            # Own session per call — lessons complete concurrently.
            title = str(topic.get("title") or "lesson").strip() or "lesson"
            if len(title) > 72:
                title = title[:69] + "…"
            async with CockpitSession() as s:
                await generate.add_topic(
                    s, studio_id=studio_id, user_id=user_id,
                    ordinal=ordinal, payload=topic,
                )
                row = await s.get(StudioBuild, build_id)
                total = int(row.lessons_total) if row is not None else 0
                done = (int(row.lessons_done) if row is not None else 0) + 1
                stage = (
                    f"Getting lessons… {done} of {total}: {title}"
                    if total > 0
                    else f"Getting lessons… {title}"
                )
                await s.execute(
                    update(StudioBuild)
                    .where(StudioBuild.id == build_id)
                    .values(
                        lessons_done=StudioBuild.lessons_done + 1,
                        stage=stage[:160],
                    )
                )
                await s.commit()

        await generate.generate_topics(
            chunks=pieces,
            studio_id=str(studio_id),
            api_key=api_key,
            model=model,
            user_id=user_id,
            filename_map=filename_map,
            on_outline=on_outline,
            on_topic=on_topic,
        )

        # Scenario Mode — best-effort, doesn't block "done".
        await _set(status="scenarios", stage="Building scenarios…")
        try:
            scenarios = await generate.generate_scenarios(
                chunks=pieces, studio_id=str(studio_id), api_key=api_key, model=model
            )
            async with CockpitSession() as s:
                await generate.persist_scenarios(
                    s, studio_id=studio_id, user_id=user_id, scenarios=scenarios
                )
        except Exception:  # noqa: BLE001
            pass

        await _set(status="done", stage="Studio ready")
    except Exception as exc:  # noqa: BLE001
        await _set(status="failed", error=str(exc))


# ---------------------------------------------------------------------------
# Answering
# ---------------------------------------------------------------------------
async def answer_question(
    *,
    vector: AsyncSession,
    shared: AsyncSession | None,
    user_id: uuid.UUID,
    studio_id: uuid.UUID,
    question: str,
    top_k: int,
) -> tuple[str, list[vectorstore.Retrieved], str]:
    settings = get_settings()
    embedder = get_embedder()
    q_vec = embedder.embed([question])[0]

    hits = await vectorstore.retrieve(
        vector,
        user_id=user_id,
        studio_id=studio_id,
        query_text=question,
        query_embedding=q_vec,
        top_k=top_k,
    )
    context_hits = hits[: settings.rag_context_k]
    context = llm.build_context_block([h.content for h in context_hits])

    api_key, model = await llm.resolve_credentials(shared)
    answer = await llm.generate(
        api_key=api_key, model=model, question=question, context=context
    )
    return answer, context_hits, model
