from typing import Any, Awaitable, Callable

ToolHandler = Callable[[dict[str, Any], dict[str, Any]], Awaitable[dict[str, Any]]]

TOOL_NAMES = [
    "plan_essay",
    "generate_outlines",
    "search_sources",
    "scrape_sources",
    "compact_sources",
    "evaluate_sources",
    "write_essay",
    "critique_essay",
    "revise_paragraph",
    "finalize_export",
    "finalize_export_humanized",
    "humanize_essay",
    "split_paragraphs",
    "ask_user",
    "echo",
]


def tool_specs() -> list[dict[str, Any]]:
    return [
        {
            "type": "function",
            "function": {
                "name": "plan_essay",
                "description": "Analyse the essay topic and create the essay plan.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "notes": {"type": "string"},
                    },
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "generate_outlines",
                "description": "Generate the essay paragraph skeleton.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "count": {
                            "type": "integer",
                            "minimum": 3,
                            "maximum": 20,
                        },
                        "selectedFocusAreas": {
                            "type": "array",
                            "items": {"type": "string"},
                        },
                    },
                    "required": ["count"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "search_sources",
                "description": "Find citable research sources.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "count": {
                            "type": "integer",
                            "minimum": 3,
                            "maximum": 20,
                        },
                        "refinement": {"type": "string"},
                    },
                    "required": ["count"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "scrape_sources",
                "description": "Fetch full source text.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "urls": {
                            "type": "array",
                            "items": {"type": "string"},
                        },
                        "limit": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 30,
                        },
                    },
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "compact_sources",
                "description": "Summarize scraped sources into citable briefs.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "urls": {
                            "type": "array",
                            "items": {"type": "string"},
                        }
                    },
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "evaluate_sources",
                "description": "Evaluate whether research sources are sufficient.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "notes": {"type": "string"},
                    },
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "write_essay",
                "description": "Write the full essay and bibliography.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "notes": {"type": "string"},
                    },
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "critique_essay",
                "description": "Critique the current essay.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "notes": {"type": "string"},
                    },
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "revise_paragraph",
                "description": "Revise one paragraph.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "paragraphIndex": {"type": "integer"},
                        "issue": {"type": "string"},
                    },
                    "required": ["paragraphIndex", "issue"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "ask_user",
                "description": "Ask the user a structured question.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "field": {"type": "string"},
                        "question": {"type": "string"},
                        "suggestions": {
                            "type": "array",
                            "items": {"type": "string"},
                        },
                        "inputType": {
                            "type": "string",
                            "enum": [
                                "text",
                                "number",
                                "select",
                                "multiselect",
                                "sourceReview",
                            ],
                        },
                        "allowCustom": {"type": "boolean"},
                    },
                    "required": ["field", "question"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "humanize_essay",
                "description": "Humanize the generated essay.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "provider": {
                            "type": "string",
                            "enum": ["StealthGPT", "UndetectableAI"],
                        }
                    },
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "split_paragraphs",
                "description": "Restore paragraph boundaries after humanization.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "finalize_export",
                "description": "Build the final essay export.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "finalEssayTitle": {"type": "string"},
                        "studentName": {"type": "string"},
                        "instructorName": {"type": "string"},
                        "institutionName": {"type": "string"},
                        "courseInfo": {"type": "string"},
                        "subjectCode": {"type": "string"},
                        "essayDate": {"type": "string"},
                    },
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "finalize_export_humanized",
                "description": "Build the humanized essay export.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                },
            },
        },
    ]