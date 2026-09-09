"""pgvector operations: write chunks and run tenant-scoped hybrid search.

Hybrid = dense (cosine over `embedding`) + lexical (ts_rank over `tsv`), combined
with Reciprocal Rank Fusion (RRF). Every query is filtered by `user_id` (and
`studio_id`) *inside* the SQL, so a user can never retrieve another user's
chunks. RRF avoids having to tune a weight between two different score scales.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


@dataclass
class Retrieved:
    chunk_id: uuid.UUID
    document_id: uuid.UUID
    ordinal: int
    content: str
    score: float


async def insert_chunks(
    session: AsyncSession,
    *,
    rows: list[dict],
) -> int:
    """Bulk-insert chunk rows. Each row: id, document_id, studio_id, user_id,
    ordinal, content, embedding (list[float]). `tsv` is computed in SQL."""
    if not rows:
        return 0
    stmt = text(
        """
        INSERT INTO chunks
            (id, document_id, studio_id, user_id, ordinal, content, embedding, tsv)
        VALUES
            (:id, :document_id, :studio_id, :user_id, :ordinal, :content,
             :embedding, to_tsvector('english', :content))
        """
    )
    await session.execute(stmt, rows)
    await session.commit()
    return len(rows)


async def update_embeddings(
    session: AsyncSession,
    *,
    rows: list[dict],
) -> int:
    """Overwrite `embedding` for existing chunks. Each row: id, embedding."""
    if not rows:
        return 0
    await session.execute(
        text("UPDATE chunks SET embedding = :embedding WHERE id = :id"),
        rows,
    )
    await session.commit()
    return len(rows)


async def fetch_studio_chunks(
    session: AsyncSession,
    *,
    studio_id: uuid.UUID,
    user_id: uuid.UUID,
) -> list[str]:
    """All chunk texts for a studio, ordered by document then position.

    This is the combined material for the studio-level generation pass, so the
    lessons cover every uploaded file rather than just the last one."""
    result = await session.execute(
        text(
            "SELECT content FROM chunks WHERE studio_id = :sid AND user_id = :uid "
            "ORDER BY document_id, ordinal"
        ),
        {"sid": str(studio_id), "uid": str(user_id)},
    )
    return [row.content for row in result]


async def delete_studio_chunks(
    session: AsyncSession,
    *,
    studio_id: uuid.UUID,
    user_id: uuid.UUID,
) -> int:
    """Delete all chunks for a studio (owner-scoped). Returns rows removed.

    Chunks live in the vector DB, which has no cross-database FK to `studios`,
    so studio deletion must clean them here explicitly."""
    result = await session.execute(
        text("DELETE FROM chunks WHERE studio_id = :sid AND user_id = :uid"),
        {"sid": str(studio_id), "uid": str(user_id)},
    )
    await session.commit()
    return result.rowcount or 0


async def retrieve(
    session: AsyncSession | None,
    *,
    user_id: uuid.UUID,
    studio_id: uuid.UUID,
    query_text: str,
    top_k: int,
    query_embedding: list[float] | None = None,
) -> list[Retrieved]:
    """Hybrid search via the Go search worker when configured, else in-process."""
    from ..config import get_settings

    settings = get_settings()
    if settings.search_service_url.strip():
        import httpx

        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                f"{settings.search_service_url.rstrip('/')}/search",
                json={
                    "user_id": str(user_id),
                    "studio_id": str(studio_id),
                    "query": query_text,
                    "top_k": top_k,
                },
            )
            resp.raise_for_status()
            hits = resp.json().get("hits") or []
        return [
            Retrieved(
                chunk_id=uuid.UUID(h["chunk_id"]),
                document_id=uuid.UUID(h["document_id"]),
                ordinal=int(h["ordinal"]),
                content=h["content"],
                score=float(h["score"]),
            )
            for h in hits
        ]
    if query_embedding is None:
        from .embeddings import get_embedder

        query_embedding = get_embedder().embed([query_text])[0]
    if session is None:
        return []
    return await hybrid_search(
        session,
        user_id=user_id,
        studio_id=studio_id,
        query_text=query_text,
        query_embedding=query_embedding,
        top_k=top_k,
    )


async def hybrid_search(
    session: AsyncSession,
    *,
    user_id: uuid.UUID,
    studio_id: uuid.UUID,
    query_text: str,
    query_embedding: list[float],
    top_k: int,
) -> list[Retrieved]:
    """Return top_k chunks fused from dense + lexical rankings (RRF, k=60)."""
    stmt = text(
        """
        WITH dense AS (
            SELECT id, document_id, ordinal, content,
                   ROW_NUMBER() OVER (ORDER BY embedding <=> :qvec) AS rnk
            FROM chunks
            WHERE user_id = :user_id AND studio_id = :studio_id
            ORDER BY embedding <=> :qvec
            LIMIT :cand
        ),
        lexical AS (
            SELECT id, document_id, ordinal, content,
                   ROW_NUMBER() OVER (
                       ORDER BY ts_rank(tsv, plainto_tsquery('english', :qtext)) DESC
                   ) AS rnk
            FROM chunks
            WHERE user_id = :user_id AND studio_id = :studio_id
              AND tsv @@ plainto_tsquery('english', :qtext)
            LIMIT :cand
        ),
        fused AS (
            SELECT id, document_id, ordinal, content,
                   SUM(1.0 / (60 + rnk)) AS score
            FROM (
                SELECT * FROM dense
                UNION ALL
                SELECT * FROM lexical
            ) u
            GROUP BY id, document_id, ordinal, content
        )
        SELECT id, document_id, ordinal, content, score
        FROM fused
        ORDER BY score DESC
        LIMIT :top_k
        """
    )
    result = await session.execute(
        stmt,
        {
            "qvec": query_embedding,
            "qtext": query_text,
            "user_id": str(user_id),
            "studio_id": str(studio_id),
            "cand": max(top_k * 4, 20),
            "top_k": top_k,
        },
    )
    return [
        Retrieved(
            chunk_id=row.id,
            document_id=row.document_id,
            ordinal=row.ordinal,
            content=row.content,
            score=float(row.score),
        )
        for row in result
    ]
