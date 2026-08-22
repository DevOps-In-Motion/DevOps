#!/usr/bin/env python3
"""Offline batch inference with Ray Data + vLLM.

Adapted from Databricks AI Runtime example:
https://docs.databricks.com/aws/en/machine-learning/ai-runtime/cli/examples/ray-batch-inference

Defaults target a small public model for local GPU testing. Scale up MODEL_SOURCE,
NUM_PROMPTS, and concurrency when you move to multi-GPU / AIR nodes.
"""

from __future__ import annotations

import os
import sys

import ray
from ray.data.llm import build_processor, vLLMEngineProcessorConfig


# Small public instruct model — no Hugging Face token required for local smoke tests.
# Scale up later (e.g. Qwen/Qwen2.5-7B-Instruct) on multi-GPU / AIR.
MODEL_SOURCE = os.environ.get("MODEL_SOURCE", "Qwen/Qwen2.5-0.5B-Instruct")
NUM_PROMPTS = int(os.environ.get("NUM_PROMPTS", "32"))
OUTPUT_PATH = os.environ.get(
    "OUTPUT_PATH",
    os.path.join(os.path.dirname(__file__), "output", "batch_inference"),
)
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "8"))
MAX_MODEL_LEN = int(os.environ.get("MAX_MODEL_LEN", "2048"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "128"))
TENSOR_PARALLEL_SIZE = int(os.environ.get("TENSOR_PARALLEL_SIZE", "1"))
# Optional hard cap on replicas; default = all GPUs in the Ray cluster.
CONCURRENCY = os.environ.get("CONCURRENCY", "").strip()


def build_prompts():
    """Build a Ray Dataset of prompts (Alpaca subset, or tiny fallback)."""
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
    # Connect to an existing cluster (`ray start`) or start a local one.
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

    if CONCURRENCY:
        concurrency = int(CONCURRENCY)
    else:
        # One vLLM replica per GPU (or per TP group).
        concurrency = max(1, total_gpus // TENSOR_PARALLEL_SIZE)

    print(
        f"Ray ready: {total_gpus} GPU(s) | model={MODEL_SOURCE} | "
        f"concurrency={concurrency} | tp={TENSOR_PARALLEL_SIZE} | "
        f"prompts={NUM_PROMPTS}",
        flush=True,
    )

    ds = build_prompts()

    config = vLLMEngineProcessorConfig(
        model_source=MODEL_SOURCE,
        engine_kwargs={
            "max_model_len": MAX_MODEL_LEN,
            "tensor_parallel_size": TENSOR_PARALLEL_SIZE,
            "enable_chunked_prefill": True,
        },
        concurrency=concurrency,
        batch_size=BATCH_SIZE,
    )

    processor = build_processor(
        config,
        preprocess=lambda row: dict(
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": row["instruction"]},
            ],
            sampling_params=dict(max_tokens=MAX_TOKENS, temperature=0.7),
        ),
        postprocess=lambda row: dict(
            instruction=row["instruction"],
            output=row["generated_text"],
        ),
    )

    # Materialize once so write + sample don't re-run inference.
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
