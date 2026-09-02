"""Ray Serve + AsyncLLMEngine: one continuous-batching scheduler per replica.

Request lifecycle (prefill → decode), not one opaque generate():
  1. ADMIT     — HTTP/Serve receives request; TTFT clock starts (metrics.StreamLatencyTracker).
  2. ROUTE     — Ray Serve picks a replica (engine actor). Ray does NOT run one
                 isolated LLM.generate() per request as a Ray task.
  3. QUEUE     — request enters this replica's AsyncLLMEngine scheduler queue.
  4. PREFILL   — compute-bound; produces first token → TTFT recorded here.
  5. DECODE    — memory-bandwidth-bound; each token gap → ITL/TPOT.
  6. STREAM    — tokens yielded to client as an async generator (not batch-and-wait).

Continuous batching lives inside AsyncLLMEngine. Do not set max_ongoing_requests=1
or block the event loop with synchronous .result() waits on the submit path.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, AsyncIterator

# Allow `python -m serving.app` from repo root of this package.
_PKG = Path(__file__).resolve().parent.parent
if str(_PKG) not in sys.path:
    sys.path.insert(0, str(_PKG))

from config import load_model_config, vllm_engine_kwargs
from metrics import StreamLatencyTracker, extract_prefix_cache_stats, server_side_cache_salt
from prompts import assemble_messages

try:
    from ray import serve
except ImportError as e:  # pragma: no cover
    raise SystemExit("Install ray[serve]: pip install 'ray[serve]'") from e


@serve.deployment(
    name="vllm-engine",
    # High enough that many in-flight requests can reach continuous batching.
    # max_ongoing_requests=1 would serialize and defeat the scheduler.
    max_ongoing_requests=int(os.environ.get("MAX_ONGOING_REQUESTS", "64")),
    ray_actor_options={"num_gpus": float(os.environ.get("SERVE_NUM_GPUS", "1"))},
)
class VLLMEngineReplica:
    """One AsyncLLMEngine per replica = one continuous-batching scheduler."""

    def __init__(self) -> None:
        from vllm.engine.arg_utils import AsyncEngineArgs
        from vllm.engine.async_llm_engine import AsyncLLMEngine

        self.cfg = load_model_config()
        kwargs = vllm_engine_kwargs(self.cfg)
        # Drop None revision keys for older vLLM
        kwargs = {k: v for k, v in kwargs.items() if v is not None}

        print(
            "Starting AsyncLLMEngine | "
            f"model={kwargs.get('model')} | "
            f"prefix_caching={kwargs.get('enable_prefix_caching')} | "
            f"chunked_prefill={kwargs.get('enable_chunked_prefill')} | "
            f"chat_template_version={self.cfg['model'].get('chat_template_version')}",
            flush=True,
        )
        engine_args = AsyncEngineArgs(**kwargs)
        self.engine = AsyncLLMEngine.from_engine_args(engine_args)
        self._req_counter = 0

        # cache_salt: single-tenant demo — not required.
        # Multi-tenant: set serving.multi_tenant / MULTI_TENANT=1 + CACHE_SALT_HMAC_SECRET.
        if not self.cfg["serving"].get("multi_tenant"):
            print(
                "cache_salt unused: single-tenant/demo deployment "
                "(enable MULTI_TENANT + CACHE_SALT_HMAC_SECRET for isolation).",
                flush=True,
            )

    async def generate_stream(self, payload: dict[str, Any]) -> AsyncIterator[str]:
        """Stream tokens; emit SSE-style JSON lines with TTFT/ITL on completion.

        Stages: ADMIT → QUEUE/PREFILL (TTFT) → DECODE (ITL) → done.
        """
        from vllm import SamplingParams

        self._req_counter += 1
        request_id = payload.get("request_id") or f"req-{self._req_counter}"
        tracker = StreamLatencyTracker()  # ADMIT — TTFT clock starts

        user_q = payload.get("prompt") or payload.get("message") or ""
        messages = assemble_messages(
            user_q,
            system=payload.get("system"),
            few_shots=payload.get("few_shots"),
            retrieved_docs=payload.get("retrieved_docs"),
            tenant_context=payload.get("tenant_context"),
            history=payload.get("history"),
            # Dynamic UUIDs/timestamps must not be prepended — footer only if needed.
            request_metadata_footer=payload.get("request_metadata_footer"),
        )

        # Prefer engine chat template (tokenizer) over manual string concat.
        tokenizer = await self.engine.get_tokenizer()
        prompt = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
        )

        sp_kwargs: dict[str, Any] = {
            "temperature": float(payload.get("temperature", 0.7)),
            "max_tokens": int(payload.get("max_tokens", 128)),
        }
        # Optional multi-tenant prefix isolation (server-derived salt only).
        if self.cfg["serving"].get("multi_tenant"):
            tenant = payload.get("tenant_id")
            if not tenant:
                yield _sse({"error": "tenant_id required when MULTI_TENANT=1"})
                return
            # Prefer SamplingParams.cache_salt when the installed vLLM supports it.
            sp_kwargs["cache_salt"] = server_side_cache_salt(str(tenant))

        try:
            sampling = SamplingParams(**sp_kwargs)
        except TypeError:
            sp_kwargs.pop("cache_salt", None)
            sampling = SamplingParams(**sp_kwargs)

        results = self.engine.generate(prompt, sampling, request_id)

        prev_text = ""
        async for out in results:
            # PREFILL complete on first non-empty delta; then DECODE.
            text = out.outputs[0].text if out.outputs else ""
            delta = text[len(prev_text) :]
            prev_text = text
            if not delta:
                continue
            tracker.on_token()
            yield _sse({"token": delta, "stage": "decode" if tracker.token_count > 1 else "prefill_done"})

        stats = tracker.as_dict()
        # Best-effort prefix-cache hit rate from engine (API varies by vLLM version).
        try:
            raw = await self.engine.do_log_stats()  # type: ignore[attr-defined]
        except Exception:
            raw = None
        if not isinstance(raw, dict):
            raw = {}
        stats.update(extract_prefix_cache_stats(raw))
        stats["chat_template_version"] = self.cfg["model"].get("chat_template_version")
        stats["stage"] = "done"
        yield _sse(stats)

    async def __call__(self, request):  # Starlette Request when HTTP ingress used
        # Ray Serve HTTP: stream body
        try:
            payload = await request.json()
        except Exception:
            payload = {"prompt": ""}
        async for chunk in self.generate_stream(payload):
            yield chunk


def _sse(obj: dict[str, Any]) -> str:
    return json.dumps(obj, ensure_ascii=False) + "\n"


def build_app():
    cfg = load_model_config()
    max_ongoing = cfg["serving"]["max_ongoing_requests_per_replica"]
    # Known gap if num_replicas > 1: Ray Serve default routing is not cache-locality
    # aware (naive balance). Flag only — do not implement Endpoint-Picker here.
    num_replicas = int(os.environ.get("NUM_REPLICAS", "1"))
    if num_replicas > 1:
        print(
            "KNOWN GAP: NUM_REPLICAS>1 uses Serve's default routing (not "
            "cache-locality-aware). Prefill/decode disagg + Endpoint Picker are "
            "out of scope for this pass.",
            flush=True,
        )
    deployment = VLLMEngineReplica.options(
        num_replicas=num_replicas,
        max_ongoing_requests=max_ongoing,
    )
    return deployment.bind()


# Entry: serve run serving.app:build_app
app = build_app()
