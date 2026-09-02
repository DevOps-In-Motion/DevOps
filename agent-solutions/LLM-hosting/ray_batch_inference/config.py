"""Shared loader for model_config.yaml + env overrides."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

_ROOT = Path(__file__).resolve().parent
_DEFAULT_CFG = _ROOT / "model_config.yaml"


def load_model_config(path: str | Path | None = None) -> dict[str, Any]:
    cfg_path = Path(path) if path else Path(os.environ.get("MODEL_CONFIG", _DEFAULT_CFG))
    data: dict[str, Any] = {}
    if cfg_path.is_file() and yaml is not None:
        with cfg_path.open() as f:
            data = yaml.safe_load(f) or {}

    model = dict(data.get("model") or {})
    engine = dict(data.get("engine") or {})
    serving = dict(data.get("serving") or {})

    # Env overrides (local smoke / AIR)
    model["source"] = os.environ.get("MODEL_SOURCE", model.get("source", "Qwen/Qwen2.5-0.5B-Instruct"))
    model["revision"] = os.environ.get("MODEL_REVISION", model.get("revision", "main"))
    model["tokenizer_revision"] = os.environ.get(
        "TOKENIZER_REVISION", model.get("tokenizer_revision", model["revision"])
    )
    model["chat_template_version"] = os.environ.get(
        "CHAT_TEMPLATE_VERSION",
        model.get("chat_template_version", "unspecified"),
    )
    model["max_model_len"] = int(
        os.environ.get("MAX_MODEL_LEN", model.get("max_model_len", 2048))
    )

    engine["enable_prefix_caching"] = _bool(
        os.environ.get("ENABLE_PREFIX_CACHING"),
        engine.get("enable_prefix_caching", True),
    )
    engine["enable_chunked_prefill"] = _bool(
        os.environ.get("ENABLE_CHUNKED_PREFILL"),
        engine.get("enable_chunked_prefill", True),
    )
    engine["tensor_parallel_size"] = int(
        os.environ.get("TENSOR_PARALLEL_SIZE", engine.get("tensor_parallel_size", 1))
    )
    engine["gpu_memory_utilization"] = float(
        os.environ.get(
            "GPU_MEMORY_UTILIZATION", engine.get("gpu_memory_utilization", 0.90)
        )
    )

    serving["max_ongoing_requests_per_replica"] = int(
        os.environ.get(
            "MAX_ONGOING_REQUESTS",
            serving.get("max_ongoing_requests_per_replica", 64),
        )
    )
    serving["multi_tenant"] = _bool(
        os.environ.get("MULTI_TENANT"), serving.get("multi_tenant", False)
    )

    return {"model": model, "engine": engine, "serving": serving}


def vllm_engine_kwargs(cfg: dict[str, Any] | None = None) -> dict[str, Any]:
    cfg = cfg or load_model_config()
    m, e = cfg["model"], cfg["engine"]
    return {
        "model": m["source"],
        "revision": m.get("revision"),
        "tokenizer_revision": m.get("tokenizer_revision"),
        "max_model_len": m["max_model_len"],
        "tensor_parallel_size": e["tensor_parallel_size"],
        "gpu_memory_utilization": e["gpu_memory_utilization"],
        "enable_prefix_caching": e["enable_prefix_caching"],
        "enable_chunked_prefill": e["enable_chunked_prefill"],
        "dtype": m.get("dtype", "auto"),
        "trust_remote_code": True,
    }


def _bool(raw: str | None, default: bool) -> bool:
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")
