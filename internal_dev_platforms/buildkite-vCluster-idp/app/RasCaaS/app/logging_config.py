"""Structured application logging for RaSCaaS (access + ops).

Env:
  LOG_LEVEL   — DEBUG | INFO | WARNING | ERROR (default INFO)
  LOG_FORMAT  — json | text  (default: json when ENVIRONMENT=production|qa, else text)
"""

from __future__ import annotations

import json
import logging
import sys
import time
import uuid
from contextvars import ContextVar
from datetime import datetime, timezone
from typing import Any
from urllib.parse import parse_qsl, urlencode

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.tracing import (
    deployment_id_ctx,
    parse_incoming_trace_id,
    span_id_ctx,
    trace_id_ctx,
    new_trace_id,
)

request_id_ctx: ContextVar[str] = ContextVar("request_id", default="-")

_SKIP_ACCESS_PATHS = frozenset({"/health", "/ready"})
_SENSITIVE_QUERY_KEYS = frozenset({"token", "access_token", "code", "state", "password", "secret"})


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
            "request_id": getattr(record, "request_id", None) or request_id_ctx.get(),
            "trace_id": getattr(record, "trace_id", None) or trace_id_ctx.get(),
            "span_id": getattr(record, "span_id", None) or span_id_ctx.get(),
        }
        dep = getattr(record, "deployment_id", None) or deployment_id_ctx.get()
        if dep and dep != "-":
            payload["deployment_id"] = dep
        for key in (
            "method",
            "path",
            "status",
            "duration_ms",
            "user",
            "client",
            "repo",
            "branch",
            "event",
            "span",
            "phase",
        ):
            val = getattr(record, key, None)
            if val is not None and val != "-":
                payload[key] = val
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        # Drop placeholder context
        if payload.get("trace_id") == "-":
            payload.pop("trace_id", None)
        if payload.get("span_id") == "-":
            payload.pop("span_id", None)
        return json.dumps(payload, default=str)


class RequestContextFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        if not getattr(record, "request_id", None):
            record.request_id = request_id_ctx.get()
        if not getattr(record, "trace_id", None):
            record.trace_id = trace_id_ctx.get()
        if not getattr(record, "span_id", None):
            record.span_id = span_id_ctx.get()
        if not getattr(record, "deployment_id", None):
            record.deployment_id = deployment_id_ctx.get()
        return True


class TextFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        rid = getattr(record, "request_id", None) or request_id_ctx.get()
        tid = getattr(record, "trace_id", None) or trace_id_ctx.get()
        base = (
            f"{self.formatTime(record, self.datefmt)} {record.levelname} "
            f"[req={rid} trace={tid}] {record.name}: {record.getMessage()}"
        )
        if record.exc_info:
            base = f"{base}\n{self.formatException(record.exc_info)}"
        return base


def setup_logging(*, level: str = "INFO", fmt: str = "text") -> None:
    root = logging.getLogger()
    root.handlers.clear()
    root.setLevel(getattr(logging, level.upper(), logging.INFO))

    handler = logging.StreamHandler(sys.stdout)
    handler.addFilter(RequestContextFilter())
    if fmt.lower() == "json":
        handler.setFormatter(JsonFormatter())
    else:
        handler.setFormatter(
            TextFormatter(
                fmt="%(asctime)s %(levelname)s %(name)s: %(message)s",
                datefmt="%Y-%m-%dT%H:%M:%S",
            )
        )
    root.addHandler(handler)

    # Keep uvicorn noisy access off — we emit our own access lines.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)
    logging.getLogger("httpx").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)


def _header_map(scope: Scope) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw_k, raw_v in scope.get("headers") or []:
        out[raw_k.decode("latin-1").lower()] = raw_v.decode("latin-1")
    return out


def _safe_path(scope: Scope) -> str:
    path = scope.get("path") or "/"
    raw_q = (scope.get("query_string") or b"").decode("latin-1")
    if not raw_q:
        return path
    parts: list[tuple[str, str]] = []
    for key, val in parse_qsl(raw_q, keep_blank_values=True):
        if key.lower() in _SENSITIVE_QUERY_KEYS:
            parts.append((key, "***"))
        else:
            parts.append((key, val))
    return f"{path}?{urlencode(parts)}" if parts else path


def _proxy_user(headers: dict[str, str]) -> str | None:
    for key in (
        "x-auth-request-email",
        "x-forwarded-email",
        "x-auth-request-user",
        "x-forwarded-user",
    ):
        val = headers.get(key)
        if val:
            return val.strip()
    return None


class AccessLogMiddleware:
    """Pure ASGI access log — safe with StreamingResponse / SSE (no BaseHTTPMiddleware)."""

    def __init__(self, app: ASGIApp, logger_name: str = "rascaas.access") -> None:
        self.app = app
        self.log = logging.getLogger(logger_name)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = _header_map(scope)
        request_id = (headers.get("x-request-id") or "").strip() or str(uuid.uuid4())
        incoming_trace = parse_incoming_trace_id(
            x_trace_id=headers.get("x-trace-id", ""),
            traceparent=headers.get("traceparent", ""),
        )
        trace_id = incoming_trace or new_trace_id()
        token_req = request_id_ctx.set(request_id)
        token_tr = trace_id_ctx.set(trace_id)
        started = time.perf_counter()
        status_code = 500
        path = scope.get("path") or "/"
        method = scope.get("method") or "?"

        async def send_wrapper(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = int(message["status"])
                raw_headers = list(message.get("headers") or [])
                raw_headers.append((b"x-request-id", request_id.encode("latin-1")))
                raw_headers.append((b"x-trace-id", trace_id.encode("latin-1")))
                message = {**message, "headers": raw_headers}
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        except Exception:
            status_code = 500
            raise
        finally:
            duration_ms = round((time.perf_counter() - started) * 1000, 1)
            if path not in _SKIP_ACCESS_PATHS:
                level = logging.INFO
                if status_code >= 500:
                    level = logging.ERROR
                elif status_code >= 400:
                    level = logging.WARNING
                client = None
                if scope.get("client"):
                    client = scope["client"][0]
                self.log.log(
                    level,
                    "%s %s → %s (%.1fms)",
                    method,
                    _safe_path(scope),
                    status_code,
                    duration_ms,
                    extra={
                        "event": "access",
                        "method": method,
                        "path": _safe_path(scope),
                        "status": status_code,
                        "duration_ms": duration_ms,
                        "user": _proxy_user(headers),
                        "client": client,
                        "request_id": request_id,
                        "trace_id": trace_id,
                    },
                )
            request_id_ctx.reset(token_req)
            trace_id_ctx.reset(token_tr)
