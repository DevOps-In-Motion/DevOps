"""Prompt assembly ordered for Automatic Prefix Caching (APC) hit rate.

Order (stable → volatile), top to bottom:
  1. Stable system instructions
  2. Stable few-shot / static context
  3. Stable retrieved docs (session-reusable RAG)
  4. Tenant / session context
  5. Conversation history
  6. Current user question (always last)

Never put timestamps, request UUIDs, or nonces near the front — they bust the
prefix hash and force full re-prefill even when the rest of the prompt is identical.
"""

from __future__ import annotations

from typing import Any

# ---------------------------------------------------------------------------
# Three caches that must not be conflated (see architecture.md):
#   KV cache      — in-GPU attention state for the *current* generation (ephemeral).
#   Prefix cache  — reuse of KV blocks *across* requests with an identical prefix.
#   Response cache — application-level (e.g. Redis) caching of *outputs*; not KV.
# ---------------------------------------------------------------------------

DEFAULT_SYSTEM = (
    "You are a helpful assistant for infrastructure and LLM-platform questions. "
    "Answer clearly and concisely."
)

# Stable few-shots — rarely change; keep ahead of any dynamic content.
DEFAULT_FEW_SHOTS: list[dict[str, str]] = [
    {
        "role": "user",
        "content": "What is continuous batching in vLLM?",
    },
    {
        "role": "assistant",
        "content": (
            "Continuous batching lets requests join and leave an in-flight GPU batch "
            "as they move through prefill and decode, instead of waiting for a fixed "
            "batch to finish together."
        ),
    },
]


def assemble_messages(
    user_question: str,
    *,
    system: str | None = None,
    few_shots: list[dict[str, str]] | None = None,
    retrieved_docs: list[str] | None = None,
    tenant_context: str | None = None,
    history: list[dict[str, str]] | None = None,
    # Dynamic values — if needed, append AFTER the user question, never before system.
    request_metadata_footer: str | None = None,
) -> list[dict[str, str]]:
    """Build chat messages in APC-friendly order.

    Returns OpenAI-style ``{role, content}`` dicts for the tokenizer chat template.
    """
    messages: list[dict[str, str]] = []

    # 1. Stable system
    messages.append({"role": "system", "content": system or DEFAULT_SYSTEM})

    # 2. Stable few-shots
    shots = DEFAULT_FEW_SHOTS if few_shots is None else few_shots
    messages.extend(shots)

    # 3. Stable / session-reusable retrieved context (still ahead of tenant + history)
    if retrieved_docs:
        doc_block = "\n\n".join(f"[doc {i+1}]\n{d}" for i, d in enumerate(retrieved_docs))
        messages.append(
            {
                "role": "system",
                "content": f"Reference documents (stable for this session):\n{doc_block}",
            }
        )

    # 4. Tenant / session context (varies more often)
    if tenant_context:
        messages.append({"role": "system", "content": f"Session context:\n{tenant_context}"})

    # 5. Conversation history
    if history:
        for turn in history:
            role = turn.get("role", "user")
            content = turn.get("content", "")
            if role in ("user", "assistant", "system") and content:
                messages.append({"role": role, "content": content})

    # 6. Current user question (always last among semantic content)
    messages.append({"role": "user", "content": user_question})

    # Optional dynamic footer — AFTER the question so it does not bust the prefix hash
    # of system + few-shot + docs + history.
    if request_metadata_footer:
        messages.append(
            {
                "role": "user",
                "content": f"[request metadata — ignore for answer]\n{request_metadata_footer}",
            }
        )

    return messages


def messages_for_batch_row(instruction: str) -> list[dict[str, str]]:
    """Batch-job helper: map a single instruction into ordered chat messages."""
    return assemble_messages(instruction)


def describe_layout() -> dict[str, Any]:
    return {
        "order": [
            "system",
            "few_shots",
            "retrieved_docs",
            "tenant_context",
            "history",
            "user_question",
            "optional_metadata_footer",
        ],
        "forbidden_near_front": ["timestamps", "request_uuids", "nonces"],
    }
