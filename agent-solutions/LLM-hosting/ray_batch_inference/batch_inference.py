#!/usr/bin/env python3
"""Offline batch inference with Ray Data + vLLM (APC + continuous-batching aware).

Architecture notes (batch vs online)
====================================
This driver is *offline batch*: Ray Data fans work across *replicas* (one
AsyncLLMEngine / vLLM engine per GPU by default). Within each replica, vLLM's
scheduler still continuous-batches microbatches of rows — Ray must NOT wrap
each row as an isolated blocking Ray *task* that starts/stops an engine.

Stages per row inside an engine replica:
  PREFILL  — prompt tokens → first generated token (dominates TTFT online)
  DECODE   — subsequent tokens (dominates ITL/TPOT online)

Offline batch waits for full completion per row before writing Parquet; it does
not stream tokens to a client. For TTFT/ITL streaming metrics, use serving/app.py.

See architecture.md for the three-cache distinction and prompt-ordering rules.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import ray
from ray.data.llm import build_processor, vLLMEngineProcessorConfig

_ROOT = Path(__file__).resolve().parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from config import load_model_config
from prompts import describe_layout, messages_for_batch_row

NUM_PROMPTS = int(os.environ.get("NUM_PROMPTS", "32"))
OUTPUT_PATH = os.environ.get(
    "OUTPUT_PATH",
    str(_ROOT / "output" / "batch_inference"),
)
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "8"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "128"))
CONCURRENCY = os.environ.get("CONCURRENCY", "").strip()


def build_prompts():
    """Build a Ray Dataset of instructions (Alpaca subset, or tiny fallback)."""
    try:
        from datasets import load_dataset

        raw = load_dataset("tatsu-lab/alpaca", split=f"train[:{NUM_PROMPTS}]")
        items = []
        for row in raw:
            instruction = row["instruction"]
            if row.get("input"):
                instruction = f"{instruction}\n\n{row['input']}"
            items.append({"instruction": instruction})
        return ray.data.from_items(items)
    except Exception as exc:
        print(f"datasets load failed ({exc}); using built-in prompts", flush=True)
        base = [
            "Explain Kubernetes in one sentence.",
            "What is Ray Data used for?",
            "Write a haiku about GPUs.",
            "Summarize what vLLM does for inference.",
        ]
        items = [{"instruction": base[i % len(base)]} for i in range(NUM_PROMPTS)]
        return ray.data.from_items(items)


def main() -> int:
    cfg = load_model_config()
    model = cfg["model"]
    engine = cfg["engine"]

    if not ray.is_initialized():
        addr = os.environ.get("RAY_ADDRESS", "auto")
        try:
            ray.init(address=addr)
        except Exception:
            print("No Ray cluster at auto; starting local Ray…", flush=True)
            ray.init()

    total_gpus = int(ray.cluster_resources().get("GPU", 0))
    if total_gpus < 1:
        print(
            "ERROR: no GPUs visible to Ray. vLLM needs at least one GPU.\n"
            "  ray start --head --num-gpus=1\n"
            "  RAY_ADDRESS=auto python batch_inference.py",
            file=sys.stderr,
        )
        return 1

    tp = int(engine["tensor_parallel_size"])
    if CONCURRENCY:
        concurrency = int(CONCURRENCY)
    else:
        # One engine replica per GPU (or per TP group). Each replica = one
        # continuous-batching scheduler. Do not inflate replicas beyond GPUs.
        concurrency = max(1, total_gpus // tp)

    print(
        f"Ray ready: {total_gpus} GPU(s) | model={model['source']} | "
        f"chat_template_version={model.get('chat_template_version')} | "
        f"replicas={concurrency} | tp={tp} | "
        f"prefix_caching={engine['enable_prefix_caching']} | "
        f"chunked_prefill={engine['enable_chunked_prefill']} | "
        f"prompts={NUM_PROMPTS}",
        flush=True,
    )
    print(f"Prompt layout: {describe_layout()['order']}", flush=True)
    print(
        "cache_salt: not used in offline batch (single-tenant job; no cross-tenant "
        "prefix isolation required).",
        flush=True,
    )
    if concurrency > 1:
        print(
            "KNOWN GAP: multiple Ray Data LLM replicas use Data's scheduling, not "
            "cache-locality-aware routing across replicas (optional follow-up).",
            flush=True,
        )

    ds = build_prompts()

    config = vLLMEngineProcessorConfig(
        model_source=model["source"],
        engine_kwargs={
            "max_model_len": model["max_model_len"],
            "tensor_parallel_size": tp,
            "enable_prefix_caching": engine["enable_prefix_caching"],
            "enable_chunked_prefill": engine["enable_chunked_prefill"],
            "gpu_memory_utilization": engine["gpu_memory_utilization"],
            "trust_remote_code": True,
        },
        concurrency=concurrency,
        batch_size=BATCH_SIZE,
    )

    # Prompt assembly: stable system + few-shots first, user instruction last
    # (see prompts.assemble_messages). No request UUIDs/timestamps in the prefix.
    processor = build_processor(
        config,
        preprocess=lambda row: dict(
            messages=messages_for_batch_row(row["instruction"]),
            sampling_params=dict(max_tokens=MAX_TOKENS, temperature=0.7),
        ),
        postprocess=lambda row: dict(
            instruction=row["instruction"],
            output=row["generated_text"],
        ),
    )

    out = processor(ds).materialize()
    os.makedirs(os.path.dirname(OUTPUT_PATH) or ".", exist_ok=True)
    out.write_parquet(OUTPUT_PATH)
    print(f"Wrote {out.count()} rows to {OUTPUT_PATH}", flush=True)

    for row in out.take(min(2, NUM_PROMPTS)):
        print("INSTRUCTION:", row["instruction"][:120], flush=True)
        print("OUTPUT:", (row.get("output") or "")[:200], flush=True)
        print("---", flush=True)

    ray.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
