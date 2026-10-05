"""Spaced repetition for flashcards — when each card comes back.

A small SM-2 variant, per user and card. A review is graded 0-3:

    0 Again  back in 1 minute (this session); ease -0.20; starts over
    1 Hard   new: back in 10 minutes; else interval x1.2 (min 1 day); ease -0.15
    2 Good   new: 1 day; second: 3 days; then interval x ease
    3 Easy   new: 4 days; then interval x ease x 1.3; ease +0.15

Ease stays within [1.3, 3.0]. `next_state` is pure so the app can show, on
each button, exactly when the card would come back (the Flutter client has a
port of it; both are tested against the same table).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.cockpit import FlashcardSchedule

MIN_EASE = 1.3
MAX_EASE = 3.0
START_EASE = 2.5


@dataclass(frozen=True)
class CardState:
    reps: int = 0
    interval_days: float = 0.0
    ease: float = START_EASE
    lapses: int = 0


def _ease(v: float) -> float:
    return round(max(MIN_EASE, min(MAX_EASE, v)), 2)


def next_state(state: CardState, grade: int) -> tuple[CardState, timedelta]:
    """The card's state after a review graded `grade` (0-3), and how long
    until it is due again."""
    g = max(0, min(3, int(grade)))
    if g == 0:
        return (
            CardState(0, 0.0, _ease(state.ease - 0.20), state.lapses + 1),
            timedelta(minutes=1),
        )
    if g == 1:
        if state.reps == 0:
            return (
                CardState(0, 0.0, _ease(state.ease - 0.15), state.lapses),
                timedelta(minutes=10),
            )
        days = max(1.0, state.interval_days * 1.2)
        return (
            CardState(state.reps + 1, days, _ease(state.ease - 0.15), state.lapses),
            timedelta(days=days),
        )
    if g == 2:
        if state.reps == 0:
            days = 1.0
        elif state.reps == 1:
            days = 3.0
        else:
            days = max(1.0, state.interval_days * state.ease)
        return (
            CardState(state.reps + 1, days, state.ease, state.lapses),
            timedelta(days=days),
        )
    days = 4.0 if state.reps == 0 else max(1.0, state.interval_days * state.ease * 1.3)
    return (
        CardState(state.reps + 1, days, _ease(state.ease + 0.15), state.lapses),
        timedelta(days=days),
    )


def _status(state: CardState) -> str:
    """learning | review, the app's FlashcardStatus (a stored card has been
    reviewed at least once, so it is never fresh)."""
    return "review" if state.reps >= 2 else "learning"


async def record(
    cockpit: AsyncSession,
    *,
    user_id: uuid.UUID,
    studio_id: uuid.UUID,
    topic_id: str,
    card_id: str,
    grade: int,
    now: datetime | None = None,
) -> dict:
    """Apply a review and store it; returns the card's new schedule fields."""
    now = now or datetime.now(UTC)
    row = (
        await cockpit.execute(
            select(FlashcardSchedule).where(
                FlashcardSchedule.user_id == user_id,
                FlashcardSchedule.card_id == card_id,
            )
        )
    ).scalar_one_or_none()
    before = (
        CardState(row.reps, row.interval_days, row.ease, row.lapses)
        if row is not None
        else CardState()
    )
    after, wait = next_state(before, grade)
    if row is None:
        row = FlashcardSchedule(
            user_id=user_id, studio_id=studio_id, topic_id=topic_id, card_id=card_id
        )
        cockpit.add(row)
    row.reps, row.interval_days = after.reps, after.interval_days
    row.ease, row.lapses = after.ease, after.lapses
    row.due_at = now + wait
    await cockpit.commit()
    return _fields(row)


def _fields(row: FlashcardSchedule) -> dict:
    state = CardState(row.reps, row.interval_days, row.ease, row.lapses)
    return {
        "reps": row.reps,
        "intervalDays": row.interval_days,
        "ease": row.ease,
        "lapses": row.lapses,
        "dueDate": row.due_at.isoformat() if row.due_at else None,
        "status": _status(state),
    }


async def schedule_map(
    cockpit: AsyncSession,
    *,
    user_id: uuid.UUID,
    studio_id: uuid.UUID,
) -> dict[str, dict]:
    """card_id -> schedule fields, to overlay onto the studio's flashcards."""
    rows = await cockpit.execute(
        select(FlashcardSchedule).where(
            FlashcardSchedule.user_id == user_id,
            FlashcardSchedule.studio_id == studio_id,
        )
    )
    return {r.card_id: _fields(r) for r in rows.scalars()}
