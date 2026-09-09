"""Document upload + ingestion.

Upload flow: file -> object storage (user-scoped key) -> Document row -> queued
IngestJob -> background task runs the RAG pipeline (extract/chunk/embed/index).
"""

from __future__ import annotations

import uuid

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    HTTPException,
    UploadFile,
    status,
)
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import CockpitSession, VectorSession, get_cockpit_session
from ..deps import get_current_user_id
from ..models.cockpit import Document, IngestJob, Studio
from ..schemas import DocumentOut, IngestJobOut
from ..services import rag
from ..services.objectstore import get_object_store

router = APIRouter(prefix="/studios/{studio_id}/documents", tags=["documents"])


async def _ingest_task(job_id: uuid.UUID, document_id: uuid.UUID) -> None:
    """Background ingestion with its own DB sessions (request session is closed)."""
    async with CockpitSession() as cockpit, VectorSession() as vector:
        document = await cockpit.get(Document, document_id)
        if document is None:
            return
        await rag.run_ingest(
            cockpit=cockpit, vector=vector, job_id=job_id, document=document
        )


@router.post("", response_model=IngestJobOut, status_code=status.HTTP_202_ACCEPTED)
async def upload_document(
    studio_id: uuid.UUID,
    background: BackgroundTasks,
    file: UploadFile,
    user_id: uuid.UUID = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_cockpit_session),
) -> IngestJob:
    studio = await session.get(Studio, studio_id)
    if studio is None or studio.user_id != user_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Studio not found")

    data = await file.read()
    document = Document(
        studio_id=studio_id,
        user_id=user_id,
        filename=file.filename or "upload.bin",
        mime=file.content_type or "application/octet-stream",
        bytes=len(data),
        object_key="",  # set below once we have the id
        status="uploaded",
    )
    session.add(document)
    await session.flush()  # assigns document.id

    key = get_object_store().key_for(user_id, document.id, document.filename)
    get_object_store().put(key, data, document.mime)
    document.object_key = key

    job = IngestJob(document_id=document.id, user_id=user_id, status="queued")
    session.add(job)
    await session.commit()
    await session.refresh(job)

    settings = get_settings()
    if settings.redis_url.strip():
        import json

        import redis as redis_sync

        r = redis_sync.from_url(settings.redis_url, decode_responses=True)
        r.rpush(
            "cockpit:ingest",
            json.dumps({"job_id": str(job.id), "document_id": str(document.id)}),
        )
        r.close()
    else:
        background.add_task(_ingest_task, job.id, document.id)
    return job


@router.get("", response_model=list[DocumentOut])
async def list_documents(
    studio_id: uuid.UUID,
    user_id: uuid.UUID = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_cockpit_session),
) -> list[Document]:
    rows = await session.execute(
        select(Document)
        .where(Document.studio_id == studio_id, Document.user_id == user_id)
        .order_by(Document.created_at.desc())
    )
    return list(rows.scalars())
