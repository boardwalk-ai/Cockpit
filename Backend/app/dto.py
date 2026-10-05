"""API DTOs mirroring the Flutter domain entities 1:1.

JSON uses the Flutter field names (camelCase) so the app's `fromJson` maps
straight across. Enum values match the Dart enum member names exactly, so a
Dart `EnumX.values.byName(json)` round-trips. This is the wire contract between
`Backend/` and `packages/study_studio`.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class _Base(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


# --- enums (values == Dart enum member names) ------------------------------
class FlashcardType(str, Enum):
    definition = "definition"
    example = "example"
    process = "process"
    compare = "compare"
    mistake = "mistake"
    formula = "formula"
    causeEffect = "causeEffect"


class FlashcardStatus(str, Enum):
    fresh = "fresh"
    learning = "learning"
    review = "review"


class QuizType(str, Enum):
    multipleChoice = "multipleChoice"
    trueFalse = "trueFalse"
    shortAnswer = "shortAnswer"
    fillBlank = "fillBlank"


class SourceFileType(str, Enum):
    pdf = "pdf"
    docx = "docx"
    pptx = "pptx"
    txt = "txt"
    image = "image"
    audio = "audio"
    video = "video"


# --- entities --------------------------------------------------------------
class FlashcardDTO(_Base):
    id: str
    topic_id: str
    front: str
    back: str
    type: FlashcardType = FlashcardType.definition
    difficulty: int = 2
    status: FlashcardStatus = FlashcardStatus.fresh
    due_date: datetime | None = None
    # Spaced repetition (services/schedule): overlaid per user at load.
    reps: int = 0
    interval_days: float = 0.0
    ease: float = 2.5
    lapses: int = 0


class QuizQuestionDTO(_Base):
    id: str
    topic_id: str
    type: QuizType
    question: str
    choices: list[str] = []
    answer: str
    explanation: str
    difficulty: int = 2
    related_concept: str | None = None


class SourceReferenceDTO(_Base):
    file_name: str
    snippet: str
    page: int | None = None


class SourceFileDTO(_Base):
    id: str
    name: str
    type: SourceFileType
    processed: bool = True


class TopicDTO(_Base):
    id: str
    studio_id: str
    title: str
    subject: str
    # 3 key points for the topic's overview; empty on studios built before it.
    summary: list[str] = []
    definition: str
    simple_explanation: str
    detailed_explanation: str
    why_it_matters: str
    examples: list[str] = []
    common_mistakes: list[str] = []
    related_topic_ids: list[str] = []
    prerequisites: list[str] = []
    memory_hooks: list[str] = []
    sources: list[SourceReferenceDTO] = []
    flashcards: list[FlashcardDTO] = []
    quiz_questions: list[QuizQuestionDTO] = []
    difficulty: int = 3
    importance: int = 3
    estimated_study_time_minutes: int = 10
    mastery: float = 0.0


class ScenarioClueDTO(_Base):
    id: str
    label: str
    detail: str


class ScenarioOptionDTO(_Base):
    id: str
    label: str


class ScenarioDTO(_Base):
    id: str
    studio_id: str
    title: str
    difficulty: int = 3
    estimated_minutes: int = 6
    skills: list[str] = []
    ai_note: str = ""
    problem: str
    question: str
    clues: list[ScenarioClueDTO] = []
    options: list[ScenarioOptionDTO] = []
    correct_option_id: str
    reasoning: str = ""
    outcome_label: str = ""
    related_topics: list[str] = []


class StudioDTO(_Base):
    id: str
    title: str
    subject: str
    created_at: datetime
    updated_at: datetime
    last_studied: datetime | None = None
    source_files: list[SourceFileDTO] = []
    topics: list[TopicDTO] = []
    scenarios: list[ScenarioDTO] = []


class MeDTO(_Base):
    id: str
    email: str | None = None
    credits: int | None = None


class AskCitationDTO(_Base):
    chunk_id: str
    document_id: str
    ordinal: int
    score: float
    snippet: str
