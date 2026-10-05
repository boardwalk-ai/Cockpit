"""Cockpit-owned business tables (studios, documents, ingest jobs).

`user_id` references the shared octopilot `users.id` but is intentionally a plain
UUID column with **no** cross-database foreign key — the databases are separate,
so ownership is enforced at the application layer (every query filters by
`user_id`). This is the deliberate boundary between shared identity and
Cockpit's own data.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..db import CockpitBase


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


class Studio(CockpitBase):
    __tablename__ = "studios"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    title: Mapped[str] = mapped_column(String(200))
    subject: Mapped[str | None] = mapped_column(String(120), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    documents: Mapped[list["Document"]] = relationship(
        back_populates="studio", cascade="all, delete-orphan"
    )

    __table_args__ = (Index("ix_studios_user_created", "user_id", "created_at"),)


class Document(CockpitBase):
    __tablename__ = "documents"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    studio_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("studios.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    filename: Mapped[str] = mapped_column(String(500))
    mime: Mapped[str] = mapped_column(String(120))
    bytes: Mapped[int] = mapped_column(default=0)
    # Object-storage key: {user_id}/{document_id}/{filename} — user-scoped path.
    object_key: Mapped[str] = mapped_column(String(1024))
    status: Mapped[str] = mapped_column(String(32), default="uploaded")  # uploaded|ingesting|ready|failed
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    studio: Mapped["Studio"] = relationship(back_populates="documents")
    jobs: Mapped[list["IngestJob"]] = relationship(
        back_populates="document", cascade="all, delete-orphan"
    )


class IngestJob(CockpitBase):
    __tablename__ = "ingest_jobs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    document_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("documents.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    status: Mapped[str] = mapped_column(String(32), default="queued")  # queued|running|done|failed
    chunks_written: Mapped[int] = mapped_column(default=0)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    document: Mapped["Document"] = relationship(back_populates="jobs")


class StudioBuild(CockpitBase):
    """Studio-level build job — the generation pass over ALL ingested material.

    Ingestion (extract/chunk/embed/store) runs per document; generation runs once
    per studio over the combined material so lessons cover every uploaded file.
    This row tracks that build so the client can stream live progress and let the
    user browse while it fills in.
    """

    __tablename__ = "studio_builds"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    studio_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("studios.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    # queued | extracting | generating | scenarios | done | failed
    status: Mapped[str] = mapped_column(String(32), default="queued")
    stage: Mapped[str] = mapped_column(String(160), default="")  # human label
    lessons_total: Mapped[int] = mapped_column(Integer, default=0)
    lessons_done: Mapped[int] = mapped_column(Integer, default=0)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class GeneratedTopic(CockpitBase):
    """A Study Object generated from the studio's RAG chunks by the LLM.

    The full TopicDTO (definition, explanations, flashcards, quizzes, …) is kept
    as a JSON `payload` so the generator can evolve the shape without a migration;
    `get_studio` assembles `StudioDTO.topics` from these rows in `ordinal` order.
    """

    __tablename__ = "generated_topics"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    studio_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("studios.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    ordinal: Mapped[int] = mapped_column(Integer, default=0)
    payload: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class TopicProgress(CockpitBase):
    """Per-user mastery of a generated topic, updated by quizzes and reviews.

    Topics live as JSON inside GeneratedTopic (id = payload["id"], e.g. "gen_…"),
    so this keys on that string topic id. Mastery is a rolling [0,1] value that
    the studio DTO overlays onto each topic at load time; the Flutter app derives
    overall mastery and weak topics from it.
    """

    __tablename__ = "topic_progress"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    studio_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("studios.id", ondelete="CASCADE"), index=True
    )
    topic_id: Mapped[str] = mapped_column(String(64), index=True)
    mastery: Mapped[float] = mapped_column(default=0.0)
    quiz_attempts: Mapped[int] = mapped_column(Integer, default=0)
    quiz_correct: Mapped[int] = mapped_column(Integer, default=0)
    flashcard_reviews: Mapped[int] = mapped_column(Integer, default=0)
    reviews: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        Index("ux_topic_progress_user_topic", "user_id", "topic_id", unique=True),
    )


class FlashcardSchedule(CockpitBase):
    """When a user's flashcard comes back (spaced repetition, services/schedule).

    Cards live as JSON inside GeneratedTopic, so this keys on the card's string
    id (payload flashcards[].id, e.g. "fc_…"). The studio DTO overlays these
    fields onto each card at load time.
    """

    __tablename__ = "flashcard_schedule"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    studio_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("studios.id", ondelete="CASCADE"), index=True
    )
    topic_id: Mapped[str] = mapped_column(String(64))
    card_id: Mapped[str] = mapped_column(String(64))
    reps: Mapped[int] = mapped_column(Integer, default=0)
    interval_days: Mapped[float] = mapped_column(default=0.0)
    ease: Mapped[float] = mapped_column(default=2.5)
    lapses: Mapped[int] = mapped_column(Integer, default=0)
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        Index("ux_flashcard_schedule_user_card", "user_id", "card_id", unique=True),
    )


class GeneratedScenario(CockpitBase):
    """An application scenario (Scenario Mode) generated from the studio's chunks.

    Same pattern as GeneratedTopic: the full ScenarioDTO is kept as a JSON
    `payload` (problem, clues, options, reasoning, …) so the shape can evolve
    without a migration. Assembled into `StudioDTO.scenarios` in `ordinal` order.
    """

    __tablename__ = "generated_scenarios"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    studio_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("studios.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    ordinal: Mapped[int] = mapped_column(Integer, default=0)
    payload: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
