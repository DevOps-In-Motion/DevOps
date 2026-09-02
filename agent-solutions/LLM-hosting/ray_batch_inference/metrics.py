"""Latency and cache metrics for prefill/decode-aware serving.

TTFT and ITL must not be conflated into a single "request latency":
  - TTFT: admission → first token (prefill + queueing dominated)
  - ITL / TPOT: gaps between successive output tokens (decode dominated)
"""

from __future__ import annotations

import hashlib
import hmac
import os
import time
from dataclasses import dataclass, field
from typing import Any, Iterator


@dataclass
class StreamLatencyTracker:
    """Track TTFT and inter-token latency while consuming a token stream."""

    admitted_at: float = field(default_factory=time.perf_counter)
    first_token_at: float | None = None
    last_token_at: float | None = None
    token_count: int = 0
    inter_token_gaps_s: list[float] = field(default_factory=list)

    def on_token(self) -> None:
        now = time.perf_counter()
        if self.first_token_at is None:
            self.first_token_at = now
        elif self.last_token_at is not None:
            self.inter_token_gaps_s.append(now - self.last_token_at)
        self.last_token_at = now
        self.token_count += 1

    @property
    def ttft_s(self) -> float | None:
        if self.first_token_at is None:
            return None
        return self.first_token_at - self.admitted_at

    @property
    def mean_itl_s(self) -> float | None:
        if not self.inter_token_gaps_s:
            return None
        return sum(self.inter_token_gaps_s) / len(self.inter_token_gaps_s)

    def as_dict(self) -> dict[str, Any]:
        return {
            "ttft_s": self.ttft_s,
            "mean_itl_s": self.mean_itl_s,
            "tpot_s": self.mean_itl_s,  # alias: time per output token ≈ mean ITL
            "output_tokens": self.token_count,
            "e2e_s": (self.last_token_at - self.admitted_at) if self.last_token_at else None,
        }


def wrap_token_stream(tokens: Iterator[str], tracker: StreamLatencyTracker | None = None):
    """Yield tokens while updating TTFT/ITL. Use at the serving entry point."""
    tracker = tracker or StreamLatencyTracker()
    for tok in tokens:
        tracker.on_token()
        yield tok
    return tracker


def server_side_cache_salt(tenant_id: str, secret: str | None = None) -> str:
    """Derive a per-tenant cache namespace (vLLM cache_salt).

    Never accept a client-supplied salt. HMAC from a trusted tenant identity.
    """
    key = (secret or os.environ.get("CACHE_SALT_HMAC_SECRET") or "").encode("utf-8")
    if not key:
        raise ValueError(
            "CACHE_SALT_HMAC_SECRET required for multi-tenant prefix isolation"
        )
    digest = hmac.new(key, tenant_id.encode("utf-8"), hashlib.sha256).hexdigest()
    return digest[:32]


def extract_prefix_cache_stats(vllm_stats: dict[str, Any] | None) -> dict[str, Any]:
    """Normalize prefix-cache hit metrics from vLLM engine stats if present.

    Field names vary by vLLM version; we probe common keys and leave unknowns null
    rather than inventing a hit rate.
    """
    if not vllm_stats:
        return {"prefix_cache_hit_rate": None, "raw_keys": []}
    candidates = [
        "gpu_prefix_cache_hit_rate",
        "prefix_cache_hit_rate",
        "cache_config.prefix_caching_hit_rate",
    ]
    hit = None
    for key in candidates:
        if key in vllm_stats:
            hit = vllm_stats[key]
            break
    # Nested probe
    if hit is None:
        for k, v in vllm_stats.items():
            if isinstance(v, (int, float)) and "prefix" in k.lower() and "hit" in k.lower():
                hit = v
                break
    return {
        "prefix_cache_hit_rate": hit,
        "raw_keys": sorted(str(k) for k in vllm_stats.keys())[:40],
    }
