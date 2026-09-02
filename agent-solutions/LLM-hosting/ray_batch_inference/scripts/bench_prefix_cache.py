#!/usr/bin/env python3
"""Rough local bench: repeated-prefix workload for TTFT / ITL / prefix-cache signal.

Requires a GPU + vLLM. Prefer the serving path when available; falls back to a
single AsyncLLMEngine in-process for smoke measurement.

  python scripts/bench_prefix_cache.py
"""

from __future__ import annotations

import asyncio
import os
import statistics
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))

from config import load_model_config, vllm_engine_kwargs
from metrics import StreamLatencyTracker
from prompts import assemble_messages


async def _run_once(engine, tokenizer, prompt: str, request_id: str, max_tokens: int):
    from vllm import SamplingParams

    tracker = StreamLatencyTracker()
    sampling = SamplingParams(temperature=0.0, max_tokens=max_tokens)
    prev = ""
    async for out in engine.generate(prompt, sampling, request_id):
        text = out.outputs[0].text if out.outputs else ""
        delta = text[len(prev) :]
        prev = text
        if delta:
            # One engine step ≈ one decode token for greedy/short gens; good enough for TTFT.
            tracker.on_token()
    return tracker.as_dict()


async def main() -> int:
    cfg = load_model_config()
    if not cfg["engine"]["enable_prefix_caching"]:
        print("WARNING: enable_prefix_caching is false — bench will not show APC gains")

    from vllm.engine.arg_utils import AsyncEngineArgs
    from vllm.engine.async_llm_engine import AsyncLLMEngine

    kwargs = {k: v for k, v in vllm_engine_kwargs(cfg).items() if v is not None}
    print(f"Bench model={kwargs.get('model')} prefix_caching={kwargs.get('enable_prefix_caching')}")
    engine = AsyncLLMEngine.from_engine_args(AsyncEngineArgs(**kwargs))
    tokenizer = await engine.get_tokenizer()

    # Shared stable prefix (system + few-shots) + varying question suffix
    questions = [
        "What is Ray Serve used for?",
        "What is continuous batching?",
        "What is prefix caching?",
        "What is TTFT?",
        "What is inter-token latency?",
    ]
    # Warm / repeat the *same* question to emphasize prefix hits on system+few-shot
    questions = questions + [questions[0]] * 3

    results = []
    for i, q in enumerate(questions):
        messages = assemble_messages(q)
        prompt = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
        stats = await _run_once(engine, tokenizer, prompt, f"bench-{i}", max_tokens=32)
        results.append(stats)
        print(f"[{i}] ttft_s={stats['ttft_s']:.4f} mean_itl_s={stats['mean_itl_s']} tokens≈{stats['output_tokens']}")

    ttfts = [r["ttft_s"] for r in results if r["ttft_s"] is not None]
    print("---")
    print(f"TTFT mean={statistics.mean(ttfts):.4f}s  median={statistics.median(ttfts):.4f}s")
    print(
        "Note: char-granularity token counting inflates token counts; use serving "
        "SSE metrics for production. Compare early vs late TTFT under APC."
    )
    if len(ttfts) >= 4:
        early, late = statistics.mean(ttfts[:2]), statistics.mean(ttfts[-2:])
        print(f"TTFT early_mean={early:.4f}s late_mean={late:.4f}s (expect late ≤ early with APC)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except Exception as exc:
        print(f"Bench failed (GPU/vLLM required): {exc}", file=sys.stderr)
        raise SystemExit(1)
