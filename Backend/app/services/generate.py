"""Turn a studio's RAG chunks into Study Objects (topics + flashcards + quizzes).

After ingestion, this reads the studio's chunks and asks the LLM (OpenRouter) to
extract a handful of topics, each with explanations, flashcards, and quiz
questions — the structured content the Flutter app renders. Output is TopicDTO-
shaped (camelCase) JSON so `get_studio` can embed it directly.

Without an LLM key it falls back to a deterministic stub (one topic from the
first chunks) so the pipeline still completes offline and in tests.
"""

from __future__ import annotations

import asyncio
import json
import uuid
from collections.abc import Awaitable, Callable

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.cockpit import GeneratedScenario, GeneratedTopic
from . import llm

# Live-build callbacks: outline size known, and each lesson as it completes.
OutlineCb = Callable[[int], Awaitable[None]]
TopicCb = Callable[[int, dict], Awaitable[None]]

# --- Pass 1: outline (one cheap call decides how many lessons) --------------
_OUTLINE_SYSTEM = (
    "You are a curriculum designer. From the study material, produce a lesson "
    "outline as strict JSON. Ground it ONLY in the material — never invent. "
    "Output JSON only: no markdown, no commentary."
)

_OUTLINE_HINT = """
List the lessons this material should be broken into — ONE per distinct concept
or section. Let the material decide the count (don't merge unrelated concepts,
don't cap it): a short note may be 2-3, a chapter 6-12, a full textbook 20+.
Cover the WHOLE material, ordered the way it should be studied.

Return ONLY JSON: an array of {"title": str, "scope": str} where scope is a
one-line note on exactly what that lesson should cover. No prose outside JSON.
""".strip()

# --- Pass 2: one rich call per lesson --------------------------------------
_DETAIL_SYSTEM = (
    "You are an expert tutor writing ONE in-depth study lesson. Use ONLY the "
    "provided material — never invent facts. Be thorough and concrete. Output a "
    "single JSON object only: no markdown, no commentary."
)


def _detail_hint(title: str, scope: str) -> str:
    return f"""
Write a rich, complete lesson on "{title}".
Focus: {scope}

Return ONLY a JSON object:
{{
  "title": "{title}",
  "definition": str,                 // 1-2 precise sentences
  "simpleExplanation": str,          // plain-language, "explain like I'm 10"
  "detailedExplanation": str,        // THOROUGH: multiple paragraphs, mechanisms, how/why it works
  "whyItMatters": str,               // 2-4 sentences on real-world relevance
  "examples": [str, ...],            // 2-4 concrete worked examples
  "commonMistakes": [str, ...],      // 2-4 pitfalls learners hit
  "memoryHooks": [str, ...],         // 1-3 mnemonics / analogies
  "flashcards": [{{"front": str, "back": str}}, ...],   // 6-10
  "quizQuestions": [                                     // 4-6, MIX the types below
    {{
      "type": "multipleChoice" | "trueFalse" | "shortAnswer" | "fillBlank",
      "question": str,                 // for fillBlank, put a "____" blank inside the sentence
      "choices": [str],                // multipleChoice: 4 options; trueFalse: ["True","False"]; shortAnswer/fillBlank: []
      "answer": str,                   // the exact correct answer; must equal one choice for multipleChoice/trueFalse
      "explanation": str
    }}, ...
  ],
  "difficulty": 1-5, "importance": 1-5
}}
Vary the quiz question types to suit THIS subject, don't use only multipleChoice:
- conceptual / reasoning topics favor multipleChoice and trueFalse
- terminology, facts, formulas, vocabulary favor shortAnswer and fillBlank
- keep shortAnswer and fillBlank answers to 1-3 words so they can be auto-graded
- when there are 3+ questions, include at least two different types
Base everything ONLY on the provided material.
""".strip()

# How much material to send to the outline pass (chars ~= tokens*4).
_CONTEXT_CHAR_BUDGET = 120_000
_OUTLINE_MAX_TOKENS = 3_000   # outline is small
_DETAIL_MAX_TOKENS = 4_000    # per-lesson rich content
_DETAIL_CONCURRENCY = 8       # parallel lesson calls
_DETAIL_TOP_K = 8            # chunks retrieved per lesson

# Quiz item types the Flutter client knows how to render (QuizType enum).
_QUIZ_TYPES = {"multipleChoice", "trueFalse", "shortAnswer", "fillBlank"}


def _parse_json(text: str):
    """Parse JSON from an LLM reply, tolerating code fences + trailing junk."""
    text = text.strip()
    if text.startswith("```"):
        text = text.split("```", 2)[1].removeprefix("json").strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # Salvage: trim to the outermost bracketed span.
    for open_c, close_c in (("[", "]"), ("{", "}")):
        start, end = text.find(open_c), text.rfind(close_c)
        if start != -1 and end > start:
            try:
                return json.loads(text[start : end + 1])
            except json.JSONDecodeError:
                # array truncated mid-object → close after the last object
                cut = text.rfind("}")
                if open_c == "[" and cut > start:
                    try:
                        return json.loads(text[start : cut + 1] + "]")
                    except json.JSONDecodeError:
                        continue
    return None


def _shape_topic(
    raw: dict, studio_id: str, sources: list[dict] | None = None
) -> dict:
    """Normalize an LLM/stub topic into a full TopicDTO dict (camelCase)."""
    topic_id = f"gen_{uuid.uuid4().hex[:10]}"

    def _flashcard(fc: dict) -> dict:
        return {
            "id": f"fc_{uuid.uuid4().hex[:8]}",
            "topicId": topic_id,
            "front": fc.get("front", ""),
            "back": fc.get("back", ""),
            "type": "definition",
            "difficulty": 2,
            "status": "fresh",
        }

    def _quiz(q: dict) -> dict:
        choices = [str(c) for c in (q.get("choices") or [])]
        qtype = q.get("type")
        if qtype not in _QUIZ_TYPES:
            # Model omitted/garbled the type → infer from the answer shape.
            if len(choices) > 2:
                qtype = "multipleChoice"
            elif len(choices) == 2:
                qtype = "trueFalse"
            else:
                qtype = "shortAnswer"
        # Normalize choices to the type so the client renders the right widget.
        if qtype == "trueFalse":
            choices = ["True", "False"]
        elif qtype in ("shortAnswer", "fillBlank"):
            choices = []
        return {
            "id": f"q_{uuid.uuid4().hex[:8]}",
            "topicId": topic_id,
            "type": qtype,
            "question": q.get("question", ""),
            "choices": choices,
            "answer": q.get("answer", ""),
            "explanation": q.get("explanation", ""),
            "difficulty": 2,
        }

    return {
        "id": topic_id,
        "studioId": studio_id,
        "title": raw.get("title", "Untitled Topic"),
        "subject": raw.get("subject", ""),
        "definition": raw.get("definition", ""),
        "simpleExplanation": raw.get("simpleExplanation", ""),
        "detailedExplanation": raw.get("detailedExplanation", ""),
        "whyItMatters": raw.get("whyItMatters", ""),
        "examples": raw.get("examples", []),
        "commonMistakes": raw.get("commonMistakes", []),
        "relatedTopicIds": [],
        "prerequisites": [],
        "memoryHooks": raw.get("memoryHooks", []),
        "sources": sources or [],
        "flashcards": [_flashcard(f) for f in (raw.get("flashcards") or [])],
        "quizQuestions": [_quiz(q) for q in (raw.get("quizQuestions") or [])],
        "difficulty": int(raw.get("difficulty", 3) or 3),
        "importance": int(raw.get("importance", 3) or 3),
        "estimatedStudyTimeMinutes": 12,
        "mastery": 0.0,
    }


def _stub_topics(chunks: list[str], studio_id: str) -> list[dict]:
    """Deterministic offline fallback — one topic summarizing the material."""
    if not chunks:
        return []
    excerpt = " ".join(chunks)[:400]
    return [
        _shape_topic(
            {
                "title": "Overview",
                "definition": excerpt,
                "simpleExplanation": "A summary generated offline (no LLM key set).",
                "detailedExplanation": excerpt,
                "whyItMatters": "Connect an LLM key to generate full study content.",
                "flashcards": [
                    {"front": "What is this studio about?", "back": excerpt[:160]},
                ],
                "quizQuestions": [
                    {
                        "question": "Is this generated from your material?",
                        "choices": ["Yes", "No"],
                        "answer": "Yes",
                        "explanation": "Built from the uploaded document's chunks.",
                    }
                ],
            },
            studio_id,
        )
    ]


def _material(chunks: list[str]) -> str:
    """Join chunks up to the context budget (whole doc for typical uploads)."""
    out: list[str] = []
    used = 0
    for c in chunks:
        if used + len(c) > _CONTEXT_CHAR_BUDGET:
            break
        out.append(c)
        used += len(c)
    return "\n\n".join(out)


async def _generate_outline(
    *, material: str, api_key: str, model: str
) -> list[dict]:
    """Pass 1 — ask the model how many lessons and what each covers."""
    raw = await llm.generate(
        api_key=api_key,
        model=model,
        system=_OUTLINE_SYSTEM,
        question=_OUTLINE_HINT,
        context=material,
        max_tokens=_OUTLINE_MAX_TOKENS,
    )
    parsed = _parse_json(raw)
    items = parsed if isinstance(parsed, list) else (parsed or {}).get("lessons", [])
    out = []
    for it in items:
        if isinstance(it, dict) and it.get("title"):
            out.append({"title": str(it["title"]), "scope": str(it.get("scope", ""))})
    return out


def _hits_to_sources(hits: list, filename_map: dict[str, str] | None) -> list[dict]:
    """Turn retrieved chunks into TopicDTO SourceReference dicts (citations).

    De-duplicates by document, keeps the top few, and trims the snippet."""
    fmap = filename_map or {}
    seen: set[str] = set()
    out: list[dict] = []
    for h in hits:
        doc_id = str(getattr(h, "document_id", ""))
        if doc_id in seen:
            continue
        seen.add(doc_id)
        snippet = (getattr(h, "content", "") or "").strip().replace("\n", " ")
        out.append({
            "fileName": fmap.get(doc_id, "Uploaded material"),
            "snippet": snippet[:220],
            "page": None,
        })
        if len(out) >= 4:
            break
    return out


async def _lesson_context(
    *,
    user_id: uuid.UUID | None,
    studio_id_uuid: uuid.UUID | None,
    title: str,
    scope: str,
    fallback: str,
) -> tuple[str, list]:
    """Retrieve the chunks most relevant to a lesson (falls back to full material).

    Returns (context_text, hits) so the caller can both ground the lesson and
    attach the retrieved chunks as citations. Uses its OWN vector session per
    call — lessons generate concurrently, and one asyncpg connection can't run
    parallel queries."""
    if user_id is None or studio_id_uuid is None:
        return fallback, []
    try:
        from .vectorstore import retrieve

        q = f"{title}. {scope}".strip()
        hits = await retrieve(
            None,
            user_id=user_id,
            studio_id=studio_id_uuid,
            query_text=q,
            top_k=_DETAIL_TOP_K,
        )
        joined = "\n\n".join(h.content for h in hits)
        return (joined or fallback), hits
    except Exception:  # noqa: BLE001 — retrieval optional; use full material
        return fallback, []


async def generate_topics(
    *,
    chunks: list[str],
    studio_id: str,
    api_key: str,
    model: str,
    user_id: uuid.UUID | None = None,
    filename_map: dict[str, str] | None = None,
    on_outline: "OutlineCb | None" = None,
    on_topic: "TopicCb | None" = None,
) -> list[dict]:
    """Two-pass generation: outline (how many lessons) → one rich call per lesson.

    Each lesson gets its own LLM call grounded in the chunks retrieved for that
    lesson, so content is deep and focused instead of a thin single-call split.
    Retrieved chunks are attached to the topic as citation sources.

    Live build: `on_outline(total)` fires once the lesson count is known, and
    `on_topic(ordinal, topic)` fires as each lesson completes — so the caller can
    persist incrementally and stream progress while the studio fills in.
    """
    if not chunks:
        return []
    if not api_key:
        return _stub_topics(chunks, studio_id)

    material = _material(chunks)
    try:
        outline = await _generate_outline(material=material, api_key=api_key, model=model)
    except Exception:  # noqa: BLE001
        outline = []
    if not outline:
        return _stub_topics(chunks, studio_id)

    if on_outline is not None:
        await on_outline(len(outline))

    sid_uuid: uuid.UUID | None
    try:
        sid_uuid = uuid.UUID(studio_id)
    except ValueError:
        sid_uuid = None

    sem = asyncio.Semaphore(_DETAIL_CONCURRENCY)

    async def _detail(ordinal: int, item: dict) -> dict | None:
        async with sem:
            context, hits = await _lesson_context(
                user_id=user_id,
                studio_id_uuid=sid_uuid,
                title=item["title"],
                scope=item["scope"],
                fallback=material,
            )
            try:
                raw = await llm.generate(
                    api_key=api_key,
                    model=model,
                    system=_DETAIL_SYSTEM,
                    question=_detail_hint(item["title"], item["scope"]),
                    context=context,
                    max_tokens=_DETAIL_MAX_TOKENS,
                )
            except Exception:  # noqa: BLE001
                return None
            obj = _parse_json(raw)
            if not isinstance(obj, dict):
                return None
            obj.setdefault("title", item["title"])
            topic = _shape_topic(obj, studio_id, _hits_to_sources(hits, filename_map))
            if on_topic is not None:
                try:
                    await on_topic(ordinal, topic)
                except Exception:  # noqa: BLE001 — persistence best-effort per lesson
                    pass
            return topic

    results = await asyncio.gather(
        *[_detail(i, it) for i, it in enumerate(outline)]
    )
    topics = [r for r in results if isinstance(r, dict)]
    return topics or _stub_topics(chunks, studio_id)


async def persist_topics(
    cockpit: AsyncSession,
    *,
    studio_id: uuid.UUID,
    user_id: uuid.UUID,
    topics: list[dict],
) -> int:
    """Replace the studio's generated topics (one-shot)."""
    await clear_topics(cockpit, studio_id=studio_id)
    for i, payload in enumerate(topics):
        cockpit.add(
            GeneratedTopic(
                studio_id=studio_id, user_id=user_id, ordinal=i, payload=payload
            )
        )
    await cockpit.commit()
    return len(topics)


async def clear_topics(cockpit: AsyncSession, *, studio_id: uuid.UUID) -> None:
    """Remove a studio's topics — call once before an incremental live build."""
    await cockpit.execute(
        delete(GeneratedTopic).where(GeneratedTopic.studio_id == studio_id)
    )
    await cockpit.commit()


async def add_topic(
    cockpit: AsyncSession,
    *,
    studio_id: uuid.UUID,
    user_id: uuid.UUID,
    ordinal: int,
    payload: dict,
) -> None:
    """Insert a single topic as it finishes — the live-fill build path."""
    cockpit.add(
        GeneratedTopic(
            studio_id=studio_id, user_id=user_id, ordinal=ordinal, payload=payload
        )
    )
    await cockpit.commit()


# ---------------------------------------------------------------------------
# Scenario Mode — application scenarios (reasoning, not recall)
# ---------------------------------------------------------------------------
_SCENARIO_SYSTEM = (
    "You are an instructional designer building APPLICATION scenarios that test "
    "reasoning, not recall — realistic situations the learner must diagnose. "
    "Ground everything ONLY in the material; never invent facts. Output strict "
    "JSON only: no markdown, no commentary."
)

_SCENARIO_HINT = """
From the material, create realistic application scenarios — situations where the
learner must REASON through a problem, not recall a fact. Make as many as the
material genuinely supports (typically 5-10), ordered easy → hard.

Return ONLY JSON: an array. Each scenario:
{
  "title": str,                    // short case name
  "difficulty": 1-5,
  "estimatedMinutes": int,
  "skills": [str],                 // 2-4 skills being tested
  "aiNote": str,                   // one line, e.g. "Multiple concepts may be required."
  "problem": str,                  // the situation, 2-4 short sentences
  "question": str,                 // what the learner must determine
  "clues": [{"label": str, "detail": str}],  // 3-5 things to investigate + what each reveals
  "options": [str, str, str, str], // 4 candidate first actions (only one is best)
  "correctIndex": 0,               // index (0-3) of the best first action
  "reasoning": str,                // WHY that action is right; rule out the others
  "outcomeLabel": str,             // short result, e.g. "Likely issue: Layer 3"
  "relatedTopics": [str]           // 2-3 related topic titles from the material
}
Base everything ONLY on the provided material. No prose outside the JSON.
""".strip()

_SCENARIO_MAX_TOKENS = 8_000


def _shape_scenario(raw: dict, studio_id: str) -> dict:
    """Normalize an LLM scenario into a full ScenarioDTO dict (camelCase)."""
    sid = f"scn_{uuid.uuid4().hex[:10]}"
    options = [
        {"id": f"opt_{i}", "label": str(o)}
        for i, o in enumerate(raw.get("options") or [])
        if str(o).strip()
    ]
    ci = raw.get("correctIndex", 0)
    ci = ci if isinstance(ci, int) and 0 <= ci < len(options) else 0
    correct_id = options[ci]["id"] if options else "opt_0"
    clues = [
        {
            "id": f"clue_{uuid.uuid4().hex[:6]}",
            "label": c.get("label", ""),
            "detail": c.get("detail", ""),
        }
        for c in (raw.get("clues") or [])
        if isinstance(c, dict) and c.get("label")
    ]
    return {
        "id": sid,
        "studioId": studio_id,
        "title": raw.get("title", "Scenario"),
        "difficulty": int(raw.get("difficulty", 3) or 3),
        "estimatedMinutes": int(raw.get("estimatedMinutes", 6) or 6),
        "skills": [str(s) for s in (raw.get("skills") or [])],
        "aiNote": raw.get("aiNote", ""),
        "problem": raw.get("problem", ""),
        "question": raw.get("question", ""),
        "clues": clues,
        "options": options,
        "correctOptionId": correct_id,
        "reasoning": raw.get("reasoning", ""),
        "outcomeLabel": raw.get("outcomeLabel", ""),
        "relatedTopics": [str(t) for t in (raw.get("relatedTopics") or [])],
    }


async def generate_scenarios(
    *, chunks: list[str], studio_id: str, api_key: str, model: str
) -> list[dict]:
    """One fast LLM call → a set of application scenarios (best-effort)."""
    if not chunks or not api_key:
        return []
    try:
        raw = await llm.generate(
            api_key=api_key,
            model=model,
            system=_SCENARIO_SYSTEM,
            question=_SCENARIO_HINT,
            context=_material(chunks),
            max_tokens=_SCENARIO_MAX_TOKENS,
        )
        parsed = _parse_json(raw)
        items = parsed if isinstance(parsed, list) else (parsed or {}).get("scenarios", [])
        return [
            _shape_scenario(s, studio_id)
            for s in items
            if isinstance(s, dict) and s.get("problem")
        ]
    except Exception:  # noqa: BLE001 — scenarios are optional; never fail ingest
        return []


async def persist_scenarios(
    cockpit: AsyncSession,
    *,
    studio_id: uuid.UUID,
    user_id: uuid.UUID,
    scenarios: list[dict],
) -> int:
    """Replace the studio's generated scenarios."""
    await cockpit.execute(
        delete(GeneratedScenario).where(GeneratedScenario.studio_id == studio_id)
    )
    for i, payload in enumerate(scenarios):
        cockpit.add(
            GeneratedScenario(
                studio_id=studio_id, user_id=user_id, ordinal=i, payload=payload
            )
        )
    await cockpit.commit()
    return len(scenarios)
