"""Lightweight deploy-scoped tracing (no OpenTelemetry dependency).

Propagates:
  X-Trace-Id / W3C traceparent → context → JSON logs → deployment → GHA → runner callbacks

Span helper emits span.start / span.end with duration_ms for ops debugging.
"""

from __future__ import annotations

import logging
import re
import time
import uuid
from contextlib import contextmanager
from contextvars import ContextVar, Token
from typing import Any, Iterator

trace_id_ctx: ContextVar[str] = ContextVar("trace_id", default="-")
span_id_ctx: ContextVar[str] = ContextVar("span_id", default="-")
deployment_id_ctx: ContextVar[str] = ContextVar("deployment_id", default="-")

_TRACEPARENT_RE = re.compile(
    r"^00-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$",
    re.IGNORECASE,
)

log = logging.getLogger("rascaas.trace")


def new_trace_id() -> str:
    return uuid.uuid4().hex


def new_span_id() -> str:
    return uuid.uuid4().hex[:16]


def parse_incoming_trace_id(*, x_trace_id: str = "", traceparent: str = "") -> str | None:
    raw = (x_trace_id or "").strip()
    if raw:
        cleaned = raw.replace("-", "")
        if re.fullmatch(r"[0-9a-fA-F]{16,64}", cleaned):
            return cleaned.lower()[:32]
        if re.fullmatch(r"[0-9a-zA-Z._-]{8,64}", raw):
            return raw[:64]
    m = _TRACEPARENT_RE.match((traceparent or "").strip())
    if m:
        return m.group(1).lower()
    return None


@contextmanager
def deployment_context(deployment_id: str, trace_id: str | None = None) -> Iterator[None]:
    t_dep = deployment_id_ctx.set(deployment_id or "-")
    t_trace: Token[str] | None = None
    if trace_id:
        t_trace = trace_id_ctx.set(trace_id)
    try:
        yield
    finally:
        deployment_id_ctx.reset(t_dep)
        if t_trace is not None:
            trace_id_ctx.reset(t_trace)


@contextmanager
def span(name: str, **attrs: Any) -> Iterator[str]:
    """Log span.start / span.end (and span.error) with duration_ms."""
    sid = new_span_id()
    token = span_id_ctx.set(sid)
    t0 = time.perf_counter()
    extra = {
        "event": "span.start",
        "span": name,
        "span_id": sid,
        "trace_id": trace_id_ctx.get(),
        "deployment_id": attrs.get("deployment_id") or deployment_id_ctx.get(),
        **{k: v for k, v in attrs.items() if v is not None},
    }
    log.info("span.start %s", name, extra=extra)
    err = False
    try:
        yield sid
    except Exception:
        err = True
        log.exception(
            "span.error %s",
            name,
            extra={
                **extra,
                "event": "span.error",
                "duration_ms": round((time.perf_counter() - t0) * 1000, 1),
            },
        )
        raise
    finally:
        duration_ms = round((time.perf_counter() - t0) * 1000, 1)
        if not err:
            log.info(
                "span.end %s (%.1fms)",
                name,
                duration_ms,
                extra={
                    **extra,
                    "event": "span.end",
                    "duration_ms": duration_ms,
                },
            )
        span_id_ctx.reset(token)
