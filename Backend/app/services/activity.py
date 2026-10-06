"""Study activity: one row per card review or quiz answer, so the app can
show the week (days studied, cards, quiz accuracy). Only counts are read
back, grouped by the user's local day."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.cockpit import StudyEvent

CARD = "card"
QUIZ = "quiz"
MAX_DAYS = 62


async def log(
    cockpit: AsyncSession,
    *,
    user_id: uuid.UUID,
    studio_id: uuid.UUID,
    topic_id: str,
    kind: str,
    correct: bool,
) -> None:
    cockpit.add(
        StudyEvent(
            user_id=user_id,
            studio_id=studio_id,
            topic_id=topic_id[:64],
            kind=kind,
            correct=correct,
        )
    )
    await cockpit.commit()


@dataclass
class Event:
    at: datetime
    kind: str
    correct: bool


def bucket(
    events: list[Event], *, days: int, tz_minutes: int, now: datetime
) -> list[dict]:
    """The last [days] local days, oldest first: cards, quiz answers and
    right answers on each."""
    shift = timedelta(minutes=tz_minutes)
    today: date = (now + shift).date()
    first = today - timedelta(days=days - 1)
    out = {
        first + timedelta(days=i): {"cards": 0, "quiz": 0, "quizRight": 0}
        for i in range(days)
    }
    for e in events:
        at = e.at if e.at.tzinfo else e.at.replace(tzinfo=UTC)
        d = (at.astimezone(UTC) + shift).date()
        row = out.get(d)
        if row is None:
            continue
        if e.kind == CARD:
            row["cards"] += 1
        elif e.kind == QUIZ:
            row["quiz"] += 1
            if e.correct:
                row["quizRight"] += 1
    return [{"date": d.isoformat(), **v} for d, v in sorted(out.items())]


async def recent(
    cockpit: AsyncSession,
    *,
    user_id: uuid.UUID,
    studio_id: uuid.UUID,
    days: int,
    tz_minutes: int,
    now: datetime | None = None,
) -> list[dict]:
    now = now or datetime.now(UTC)
    days = max(1, min(days, MAX_DAYS))
    since = now - timedelta(days=days + 1)
    rows = await cockpit.execute(
        select(StudyEvent.at, StudyEvent.kind, StudyEvent.correct).where(
            StudyEvent.user_id == user_id,
            StudyEvent.studio_id == studio_id,
            StudyEvent.at >= since,
        )
    )
    events = [Event(at, kind, correct) for at, kind, correct in rows]
    return bucket(events, days=days, tz_minutes=tz_minutes, now=now)
