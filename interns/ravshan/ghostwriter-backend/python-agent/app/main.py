import asyncio
import json
import os
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from .tools.executor import execute_tool
from .tools.registry import tool_specs

app = FastAPI(title="GhostWriter Agent", version="1.0.0")

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

runs: dict[str, dict[str, Any]] = {}


class StartRequest(BaseModel):
    draft: dict[str, Any] = Field(default_factory=dict)


class AnswerRequest(BaseModel):
    field: str
    value: Any


class MessageRequest(BaseModel):
    text: str


def has_real_openrouter_key() -> bool:
    key = os.getenv("OPENROUTER_API_KEY", "").strip()

    return bool(
        key
        and key != "YOUR_OPENROUTER_KEY"
        and "YOUR_REAL_KEY" not in key
    )


async def emit(
    run: dict[str, Any],
    event: dict[str, Any],
):
    await run["events"].put(event)


def initial_context(
    draft: dict[str, Any],
) -> dict[str, Any]:
    return {
        "instruction": str(
            draft.get("instruction", "")
        ).strip(),
        "outlines": [],
        "searchResults": [],
        "scrapedSources": [],
        "compactedSources": [],
        "paragraphs": [],
        "critiqueIssues": [],
        "revisionRounds": 0,
        "revisionHistory": [],
        "draftSettings": dict(
            draft.get("detectedSettings") or {}
        ),
        "formatAnswers": {},
        "sourceReviewNotes": [],
        "autoExcludedUrls": [],
        "userDirectiveLog": [],
        "exportReady": False,
    }


SYSTEM_PROMPT = """
You are GhostWriter, an autonomous academic writing agent.

Workflow:
1 plan_essay
2 ask_user for essayFocus
3 generate_outlines
4 search_sources
5 scrape_sources
6 compact_sources
7 evaluate_sources
8 ask_user wordCount
9 ask_user citationStyle
10 write_essay
11 formatting metadata
12 finalize_export
13 ask humanizerChoice
14 optionally humanize and split paragraphs

Do not ask for paragraph count.
Keep replies terse.
Use tools whenever possible.
"""


async def call_model(
    messages: list[dict[str, Any]],
) -> tuple[dict[str, Any], dict[str, Any]]:
    api_key = os.getenv("OPENROUTER_API_KEY", "")
    model = (
        os.getenv("GHOSTWRITER_ORCHESTRATOR_MODEL")
        or os.getenv("OPENROUTER_MODEL")
        or "openai/gpt-4o-mini"
    )

    payload = {
        "model": model,
        "messages": messages,
        "tools": tool_specs(),
        "tool_choice": "auto",
        "temperature": 0.3,
    }

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://octopilotai.com",
        "X-Title": "OctoPilot AI",
    }

    last_error = None

    async with httpx.AsyncClient(timeout=90) as client:
        for delay in (0, 0.4, 0.8):
            if delay:
                await asyncio.sleep(delay)

            try:
                response = await client.post(
                    OPENROUTER_URL,
                    headers=headers,
                    json=payload,
                )

                if response.status_code in {
                    408,
                    409,
                    425,
                    429,
                    500,
                    502,
                    503,
                    504,
                }:
                    last_error = RuntimeError(
                        response.text
                    )
                    continue

                response.raise_for_status()

                data = response.json()

                return (
                    data["choices"][0]["message"],
                    data.get("usage") or {},
                )

            except Exception as exc:
                last_error = exc

    raise last_error or RuntimeError(
        "OpenRouter request failed"
    )


def apply_answer(
    field: str,
    value: Any,
    context: dict[str, Any],
):
    if field == "wordCount":
        try:
            value = int(value)
        except Exception:
            pass

        context.setdefault(
            "draftSettings",
            {},
        )["wordCount"] = value

        return

    if field in {
        "citationStyle",
        "tone",
        "keywords",
    }:
        context.setdefault(
            "draftSettings",
            {},
        )[field] = value

        return

    if field == "sourceReview":
        context["sourceReviewNotes"] = value
        return

    if field == "humanizerChoice":
        context["humanizerChoice"] = value
        return

    if field == "paragraphSplitChoice":
        context["paragraphSplitChoice"] = value
        return

    context.setdefault(
        "formatAnswers",
        {},
    )[field] = value


async def wait_for_answer(
    run: dict[str, Any],
    field: str,
) -> Any:
    run["pendingField"] = field
    run["status"] = "waiting_for_user"

    while True:
        answer = await run["answers"].get()

        if answer["field"] == field:
            run["pendingField"] = None
            run["status"] = "running"

            return answer["value"]


async def demo_agent_loop(
    run_id: str,
):
    run = runs[run_id]
    context = run["context"]

    run["status"] = "running"

    instruction = (
        context.get("instruction")
        or "Untitled essay"
    )

    await emit(
        run,
        {
            "type": "thought",
            "text": "Planning essay workflow.",
        },
    )

    await emit(
        run,
        {
            "type": "step_start",
            "id": "demo-plan",
            "title": "Plan Essay",
            "tool": "plan_essay",
            "args": {},
        },
    )

    context["essayTopic"] = instruction
    context["essayType"] = "Argumentative"

    context["plan"] = {
        "thesis": (
            "AI can improve cybersecurity when "
            "combined with skilled human oversight."
        ),
        "paragraphCount": 5,
        "searchQueries": [
            "AI cybersecurity benefits",
            "AI cyber threat detection",
            "AI cybersecurity risks",
        ],
        "notes": (
            "Local demo fallback because no "
            "OpenRouter key is configured."
        ),
        "essayFocusOptions": [
            "Threat detection",
            "Automation",
            "Human oversight",
            "AI security risks",
        ],
    }

    await emit(
        run,
        {
            "type": "context_update",
            "patch": context,
        },
    )

    await emit(
        run,
        {
            "type": "step_done",
            "id": "demo-plan",
            "summary": "plan_essay completed",
        },
    )

    await emit(
        run,
        {
            "type": "question",
            "field": "wordCount",
            "question": (
                "How many words should the essay be?"
            ),
            "options": [
                {
                    "label": "500",
                    "value": "500",
                },
                {
                    "label": "800",
                    "value": "800",
                },
                {
                    "label": "1200",
                    "value": "1200",
                },
                {
                    "label": "2000",
                    "value": "2000",
                },
                {
                    "label": "3000",
                    "value": "3000",
                },
            ],
            "inputType": "select",
            "allowCustom": True,
        },
    )

    word_count = await wait_for_answer(
        run,
        "wordCount",
    )

    apply_answer(
        "wordCount",
        word_count,
        context,
    )

    await emit(
        run,
        {
            "type": "context_update",
            "patch": context,
        },
    )

    await emit(
        run,
        {
            "type": "question",
            "field": "citationStyle",
            "question": (
                "Which citation style should I use?"
            ),
            "options": [
                {
                    "label": "APA",
                    "value": "APA",
                },
                {
                    "label": "MLA",
                    "value": "MLA",
                },
                {
                    "label": "Chicago",
                    "value": "Chicago",
                },
                {
                    "label": "Harvard",
                    "value": "Harvard",
                },
                {
                    "label": "IEEE",
                    "value": "IEEE",
                },
                {
                    "label": "None",
                    "value": "None",
                },
            ],
            "inputType": "select",
            "allowCustom": False,
        },
    )

    citation_style = await wait_for_answer(
        run,
        "citationStyle",
    )

    apply_answer(
        "citationStyle",
        citation_style,
        context,
    )

    await emit(
        run,
        {
            "type": "context_update",
            "patch": context,
        },
    )

    context["exportReady"] = True

    context["exportDoc"] = {
        "title": "Ghostwriter Demo Draft",
        "pages": [
            {
                "id": 1,
                "title": "Essay",
                "html": (
                    "<p>GhostWriter backend "
                    "demo completed.</p>"
                ),
                "plainText": (
                    "GhostWriter backend "
                    "demo completed."
                ),
            }
        ],
        "profile": {
            "defaultFont": "Times New Roman",
            "lineHeight": 2,
            "marginInch": 1,
            "headerText": "",
            "showPageNumber": True,
            "pageNumberStartPage": 1,
            "pageNumberStartNumber": 1,
        },
    }

    await emit(
        run,
        {
            "type": "assistant_message",
            "text": (
                "Demo workflow completed. "
                "OpenRouter can be enabled by "
                "setting OPENROUTER_API_KEY."
            ),
        },
    )

    run["status"] = "finished"

    await emit(
        run,
        {
            "type": "done",
            "exportDoc": context["exportDoc"],
        },
    )


async def agent_loop(
    run_id: str,
):
    if not has_real_openrouter_key():
        await demo_agent_loop(run_id)
        return

    run = runs[run_id]
    context = run["context"]

    instruction = context.get("instruction")

    user_brief = (
        f"USER INSTRUCTION:\n"
        f"{instruction}\n\nProceed."
        if instruction
        else (
            "No essay instruction supplied. "
            "Ask the user for the topic."
        )
    )

    messages: list[dict[str, Any]] = [
        {
            "role": "system",
            "content": SYSTEM_PROMPT,
        },
        {
            "role": "user",
            "content": user_brief,
        },
    ]

    run["status"] = "running"

    try:
        for step_number in range(40):
            if run["cancelled"]:
                return

            if run["pauseRequested"]:
                run["pauseRequested"] = False

                await emit(
                    run,
                    {
                        "type": "question",
                        "field": "userDirective",
                        "question": (
                            "What would you like "
                            "me to change?"
                        ),
                        "inputType": "text",
                        "allowCustom": True,
                    },
                )

                directive = await wait_for_answer(
                    run,
                    "userDirective",
                )

                context.setdefault(
                    "userDirectiveLog",
                    [],
                ).append(
                    str(directive)
                )

                messages.append(
                    {
                        "role": "user",
                        "content": (
                            "USER DIRECTIVE: "
                            f"{directive}"
                        ),
                    }
                )

            while not run["messages"].empty():
                text = await run["messages"].get()

                messages.append(
                    {
                        "role": "user",
                        "content": text,
                    }
                )

            message, usage = await call_model(
                messages
            )

            if usage:
                await emit(
                    run,
                    {
                        "type": "token_usage",
                        "promptTokens": int(
                            usage.get(
                                "prompt_tokens",
                                0,
                            )
                        ),
                        "completionTokens": int(
                            usage.get(
                                "completion_tokens",
                                0,
                            )
                        ),
                        "totalTokens": int(
                            usage.get(
                                "total_tokens",
                                0,
                            )
                        ),
                    },
                )

            content = message.get("content") or ""

            if content:
                await emit(
                    run,
                    {
                        "type": "assistant_message",
                        "text": content,
                    },
                )

            messages.append(message)

            tool_calls = (
                message.get("tool_calls")
                or []
            )

            if not tool_calls:
                if (
                    context.get("exportReady")
                    or content.strip().upper()
                    == "DONE"
                ):
                    run["status"] = "finished"

                    await emit(
                        run,
                        {
                            "type": "done",
                            "exportDoc": (
                                context.get(
                                    "exportDoc"
                                )
                            ),
                        },
                    )
                    return

                await emit(
                    run,
                    {
                        "type": "question",
                        "field": "userMessage",
                        "question": (
                            "What would you like "
                            "to do next?"
                        ),
                        "inputType": "text",
                        "allowCustom": True,
                    },
                )

                value = await wait_for_answer(
                    run,
                    "userMessage",
                )

                messages.append(
                    {
                        "role": "user",
                        "content": str(value),
                    }
                )

                continue

            for tool_call in tool_calls:
                if run["cancelled"]:
                    return

                function = (
                    tool_call.get("function")
                    or {}
                )

                tool_name = function.get(
                    "name",
                    "",
                )

                try:
                    args = json.loads(
                        function.get(
                            "arguments"
                        )
                        or "{}"
                    )
                except json.JSONDecodeError:
                    args = {}

                step_id = tool_call.get(
                    "id",
                    f"step-{step_number}",
                )

                await emit(
                    run,
                    {
                        "type": "step_start",
                        "id": step_id,
                        "title": (
                            tool_name.replace(
                                "_",
                                " ",
                            ).title()
                        ),
                        "tool": tool_name,
                        "args": args,
                    },
                )

                try:
                    result = await asyncio.wait_for(
                        execute_tool(
                            tool_name,
                            args,
                            context,
                        ),
                        timeout=300,
                    )

                    if tool_name == "ask_user":
                        await emit(
                            run,
                            {
                                "type": "question",
                                "field": result[
                                    "field"
                                ],
                                "question": result[
                                    "question"
                                ],
                                "options": (
                                    result.get(
                                        "options",
                                        [],
                                    )
                                ),
                                "suggestions": (
                                    result.get(
                                        "suggestions",
                                        [],
                                    )
                                ),
                                "inputType": (
                                    result.get(
                                        "inputType",
                                        "text",
                                    )
                                ),
                                "allowCustom": (
                                    result.get(
                                        "allowCustom",
                                        False,
                                    )
                                ),
                            },
                        )

                        value = await wait_for_answer(
                            run,
                            result["field"],
                        )

                        apply_answer(
                            result["field"],
                            value,
                            context,
                        )

                        result = {
                            "answer": value
                        }

                    await emit(
                        run,
                        {
                            "type": "context_update",
                            "patch": context,
                        },
                    )

                    await emit(
                        run,
                        {
                            "type": "step_done",
                            "id": step_id,
                            "summary": (
                                f"{tool_name} "
                                "completed"
                            ),
                        },
                    )

                    messages.append(
                        {
                            "role": "tool",
                            "tool_call_id": (
                                tool_call["id"]
                            ),
                            "content": json.dumps(
                                result,
                                default=str,
                            ),
                        }
                    )

                except Exception as exc:
                    await emit(
                        run,
                        {
                            "type": "step_error",
                            "id": step_id,
                            "error": str(exc),
                            "retryable": True,
                        },
                    )

                    messages.append(
                        {
                            "role": "tool",
                            "tool_call_id": (
                                tool_call["id"]
                            ),
                            "content": json.dumps(
                                {
                                    "error": str(exc)
                                }
                            ),
                        }
                    )

        raise RuntimeError(
            "GhostWriter reached maximum 40 steps"
        )

    except asyncio.CancelledError:
        return

    except Exception as exc:
        run["status"] = "error"

        await emit(
            run,
            {
                "type": "fatal",
                "error": str(exc),
            },
        )


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "ghostwriter-python-agent",
        "openrouter": has_real_openrouter_key(),
        "demoMode": not has_real_openrouter_key(),
    }


@app.post("/runs/{run_id}/start")
async def start_run(
    run_id: str,
    request: StartRequest,
):
    if run_id in runs:
        return {
            "ok": True,
            "runId": run_id,
        }

    run = {
        "id": run_id,
        "draft": request.draft,
        "context": initial_context(
            request.draft
        ),
        "events": asyncio.Queue(),
        "answers": asyncio.Queue(),
        "messages": asyncio.Queue(),
        "pendingField": None,
        "pauseRequested": False,
        "cancelled": False,
        "status": "pending",
    }

    runs[run_id] = run

    asyncio.create_task(
        agent_loop(run_id)
    )

    return {
        "ok": True,
        "runId": run_id,
        "mode": (
            "agentic"
            if has_real_openrouter_key()
            else "demo"
        ),
    }


@app.get("/runs/{run_id}/events")
async def stream_events(
    run_id: str,
):
    run = runs.get(run_id)

    if not run:
        raise HTTPException(
            404,
            "Run not found",
        )

    async def generator():
        while True:
            try:
                event = await asyncio.wait_for(
                    run["events"].get(),
                    timeout=15,
                )

                yield (
                    "data: "
                    + json.dumps(
                        event,
                        default=str,
                    )
                    + "\n\n"
                )

                if event["type"] in {
                    "done",
                    "fatal",
                }:
                    return

            except asyncio.TimeoutError:
                yield ": keep-alive\n\n"

    return StreamingResponse(
        generator(),
        media_type="text/event-stream",
    )


@app.post("/runs/{run_id}/answer")
async def answer(
    run_id: str,
    request: AnswerRequest,
):
    run = runs.get(run_id)

    if not run:
        raise HTTPException(
            404,
            "Run not found",
        )

    if (
        run.get("pendingField")
        != request.field
    ):
        raise HTTPException(
            409,
            (
                "No pending question "
                f'for field "{request.field}"'
            ),
        )

    await run["answers"].put(
        {
            "field": request.field,
            "value": request.value,
        }
    )

    return {"ok": True}


@app.post("/runs/{run_id}/message")
async def message(
    run_id: str,
    request: MessageRequest,
):
    run = runs.get(run_id)

    if not run:
        raise HTTPException(
            404,
            "Run not found",
        )

    if not request.text.strip():
        raise HTTPException(
            400,
            "text is required",
        )

    await run["messages"].put(
        request.text.strip()
    )

    return {"ok": True}


@app.post("/runs/{run_id}/pause")
async def pause(
    run_id: str,
):
    run = runs.get(run_id)

    if not run:
        raise HTTPException(
            404,
            "Run not found",
        )

    run["pauseRequested"] = True

    return {"ok": True}


@app.post("/runs/{run_id}/cancel")
async def cancel(
    run_id: str,
):
    run = runs.get(run_id)

    if not run:
        raise HTTPException(
            404,
            "Run not found",
        )

    run["cancelled"] = True
    run["status"] = "cancelled"

    await emit(
        run,
        {
            "type": "fatal",
            "error": "Run cancelled by user.",
        },
    )

    return {"ok": True}