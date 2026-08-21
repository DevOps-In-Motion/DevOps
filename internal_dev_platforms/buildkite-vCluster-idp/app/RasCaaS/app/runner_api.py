"""Runner callback API — GitHub Actions posts progress into RaSCaaS (no oauth2)."""

from __future__ import annotations

import hmac
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel, Field, model_validator

from app.config import settings
from app.deployments import (
    LIFECYCLE_ACTIVE,
    LIFECYCLE_DELETED,
    LIFECYCLE_SUPERSEDED,
    ClusterPhase,
    DeploymentStore,
)
from app.lifecycle import schedule_deletion_verification
from app.logging_config import get_logger
from app.tracing import deployment_context, span

log = get_logger("rascaas.runner")

router = APIRouter(prefix="/api/runner", tags=["runner"])

MAX_BODY_BYTES = 64 * 1024
MAX_LINES = 100
MAX_LINE_LEN = 4000

PhaseName = Literal["provisioning", "syncing", "ready", "failed"]
LevelName = Literal["info", "warn", "warning", "error"]


class RunnerEventBody(BaseModel):
    deployment_id: str = Field(..., min_length=1, max_length=64)
    line: str | None = None
    lines: list[str] | None = None
    level: LevelName = "info"
    phase: PhaseName | None = None
    message: str | None = None
    run_id: int | None = None
    run_url: str | None = None
    trace_id: str | None = None

    @model_validator(mode="after")
    def require_lines(self) -> RunnerEventBody:
        if not (self.line or self.lines):
            raise ValueError("Provide line or lines")
        return self

    def iter_lines(self) -> list[str]:
        out: list[str] = []
        if self.lines:
            out.extend(self.lines)
        if self.line:
            out.append(self.line)
        cleaned: list[str] = []
        for raw in out:
            text = (raw or "").strip("\n")
            if not text:
                continue
            if len(text) > MAX_LINE_LEN:
                text = text[: MAX_LINE_LEN - 1] + "…"
            cleaned.append(text)
            if len(cleaned) >= MAX_LINES:
                break
        return cleaned


class RunnerDeletionBody(BaseModel):
    """Deletion event: a deleter POSTs this when tearing a vCluster down."""

    deployment_id: str | None = Field(default=None, max_length=64)
    vcluster_name: str | None = Field(default=None, max_length=253)
    trace_id: str | None = None
    message: str | None = None

    @model_validator(mode="after")
    def require_target(self) -> RunnerDeletionBody:
        if not ((self.deployment_id or "").strip() or (self.vcluster_name or "").strip()):
            raise ValueError("Provide deployment_id or vcluster_name")
        return self


def _extract_token(
    authorization: str | None,
    x_rascaas_token: str | None,
) -> str:
    if x_rascaas_token and x_rascaas_token.strip():
        return x_rascaas_token.strip()
    if authorization:
        parts = authorization.strip().split(None, 1)
        if len(parts) == 2 and parts[0].lower() == "bearer":
            return parts[1].strip()
        return authorization.strip()
    return ""


def require_runner_token(
    authorization: str | None = Header(default=None),
    x_rascaas_token: str | None = Header(default=None, alias="X-RaSCaaS-Token"),
) -> None:
    expected = (settings.runner_callback_token or "").strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Runner callback token not configured",
        )
    provided = _extract_token(authorization, x_rascaas_token)
    if not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid runner token",
        )


def get_store_dep() -> DeploymentStore:
    from app.main import get_store

    return get_store()


@router.post("/events")
async def post_runner_events(
    request: Request,
    body: RunnerEventBody,
    _auth: None = Depends(require_runner_token),
    store: DeploymentStore = Depends(get_store_dep),
):
    raw_len = request.headers.get("content-length")
    if raw_len and raw_len.isdigit() and int(raw_len) > MAX_BODY_BYTES:
        raise HTTPException(status_code=413, detail="Body too large")

    dep = store.get(body.deployment_id)
    if dep is None:
        raise HTTPException(status_code=404, detail="Deployment not found")

    trace_id = (body.trace_id or dep.trace_id or "").strip()
    if trace_id and not dep.trace_id:
        dep.trace_id = trace_id

    level = "warn" if body.level == "warning" else body.level
    lines = body.iter_lines()
    if not lines:
        raise HTTPException(status_code=422, detail="No non-empty lines")

    with deployment_context(dep.id, dep.trace_id or trace_id or None):
        with span(
            "runner.events",
            deployment_id=dep.id,
            phase=body.phase,
            n_lines=len(lines),
        ):
            if body.run_id is not None:
                dep.run_id = body.run_id
            if body.run_url:
                dep.run_url = body.run_url

            if body.phase:
                try:
                    dep.phase = ClusterPhase(body.phase)
                except ValueError as exc:
                    raise HTTPException(
                        status_code=422, detail=f"Invalid phase: {body.phase}"
                    ) from exc
                if body.message:
                    dep.message = body.message
                elif body.phase == "provisioning":
                    dep.message = "Provisioning (runner)"
                elif body.phase == "syncing":
                    dep.message = "Syncing (runner)"
                elif body.phase == "ready":
                    dep.message = "Stack is ready"
                elif body.phase == "failed":
                    dep.message = "Deployment failed (runner)"

            for line in lines:
                store.append_event(dep, line, level=level, source="runner")

            store.update(dep)

            # Event-based lock ops only for the *current* attempt.
            # Superseded/deleted rows must not refresh or re-acquire Redis (zombie GHA).
            if dep.vcluster_name and dep.lifecycle == LIFECYCLE_ACTIVE:
                from app.locks import get_lock_store

                if body.phase == "ready":
                    await get_lock_store().create_from_ready(dep.vcluster_name, dep.id)
                    store.append_event(
                        dep,
                        f"Ready — live lock set on {dep.vcluster_name} (8d); inflight cleared",
                        source="system",
                    )
                elif body.phase == "failed":
                    # Release only this attempt's inflight key. Never touch live (8d)
                    # held by a successful prior deploy.
                    await get_lock_store().release_inflight(dep.vcluster_name, dep.id)
                    store.append_event(
                        dep,
                        f"Deploy failed — released inflight lock for attempt {dep.id} on {dep.vcluster_name}",
                        level="error",
                        source="system",
                    )
            elif (
                dep.vcluster_name
                and body.phase in ("ready", "failed")
                and dep.lifecycle in (LIFECYCLE_SUPERSEDED, LIFECYCLE_DELETED)
            ):
                store.append_event(
                    dep,
                    f"Ignored lock side-effect for {body.phase} — lifecycle={dep.lifecycle}",
                    source="system",
                )

            log.info(
                "runner events deployment_id=%s n=%s phase=%s",
                dep.id,
                len(lines),
                body.phase or dep.phase.value,
                extra={
                    "event": "runner_events",
                    "deployment_id": dep.id,
                    "phase": body.phase or dep.phase.value,
                    "trace_id": dep.trace_id,
                },
            )
            return {
                "ok": True,
                "events": len(lines),
                "deployment_id": dep.id,
                "trace_id": dep.trace_id,
                "phase": dep.phase.value,
            }


@router.post("/deleted")
async def post_runner_deleted(
    body: RunnerDeletionBody,
    _auth: None = Depends(require_runner_token),
    store: DeploymentStore = Depends(get_store_dep),
):
    """Deletion event → mark deleting (still shown), re-verify teardown after a delay.

    The deployment stays visible until the follow-up cluster check confirms the
    vCluster is gone. If it is still live at that point, it flips back to active.
    """
    dep = None
    if body.deployment_id and body.deployment_id.strip():
        dep = store.get(body.deployment_id.strip())
    if dep is None and body.vcluster_name and body.vcluster_name.strip():
        dep = store.find_visible_by_vcluster(body.vcluster_name.strip())
    if dep is None:
        raise HTTPException(status_code=404, detail="Deployment not found")

    trace_id = (body.trace_id or dep.trace_id or "").strip()
    if trace_id and not dep.trace_id:
        dep.trace_id = trace_id

    delay = settings.delete_verify_delay_s
    with deployment_context(dep.id, dep.trace_id or trace_id or None):
        with span("runner.deleted", deployment_id=dep.id, vcluster=dep.vcluster_name):
            store.mark_deleting(
                dep,
                body.message
                or f"Deletion event received — verifying teardown of {dep.vcluster_name} in {delay}s",
            )
            schedule_deletion_verification(
                store, dep.id, settings.vcluster_host_namespace, float(delay)
            )
            log.info(
                "deletion event deployment_id=%s vcluster=%s verify_in=%ss",
                dep.id,
                dep.vcluster_name,
                delay,
                extra={
                    "event": "deletion_event",
                    "deployment_id": dep.id,
                    "vcluster": dep.vcluster_name,
                    "trace_id": dep.trace_id,
                },
            )
            return {
                "ok": True,
                "deployment_id": dep.id,
                "vcluster_name": dep.vcluster_name,
                "lifecycle": dep.lifecycle,
                "verify_in_s": delay,
                "trace_id": dep.trace_id,
            }
