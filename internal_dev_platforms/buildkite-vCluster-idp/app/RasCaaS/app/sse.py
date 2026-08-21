"""Server-Sent Events stream for deployment / GitHub Actions / runner status."""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator
from typing import TYPE_CHECKING

from app.deployments import ClusterPhase, DeploymentStore, _now

if TYPE_CHECKING:
    from app.github import GitHubClient


def _sse(payload: dict) -> str:
    return f"data: {json.dumps(payload)}\n\n"


def _is_terminal(dep) -> bool:
    return dep.phase in (ClusterPhase.READY, ClusterPhase.FAILED)


def _event_key(entry: dict) -> str:
    return f"{entry.get('ts','')}|{entry.get('source','')}|{entry.get('line','')}"


async def _emit_new_store_events(
    dep_id: str,
    store: DeploymentStore,
    seen: set[str],
) -> AsyncIterator[str]:
    """Yield SSE for runner/system events appended since last watermark."""
    dep = store.get(dep_id)
    if dep is None:
        return
    emitted = False
    for entry in dep.events:
        key = _event_key(entry)
        if key in seen:
            continue
        seen.add(key)
        emitted = True
        yield _sse(
            {
                "type": "log",
                "line": entry.get("line"),
                "level": entry.get("level"),
                "source": entry.get("source"),
                "trace_id": entry.get("trace_id") or dep.trace_id,
                "deployment": dep.to_dict(),
                "run_url": dep.run_url,
            }
        )
    if emitted:
        yield _sse(
            {
                "type": "status",
                "deployment": dep.to_dict(),
                "run_url": dep.run_url,
            }
        )


async def _mock_tick(dep_id: str, store: DeploymentStore) -> AsyncIterator[str]:
    """Simulate GitHub + cluster progress in development."""
    timeline = [
        (0, "Dispatch accepted by RaSCaaS"),
        (2, "Waiting for GitHub Actions run…"),
        (4, "Workflow run queued (mock)"),
        (8, "Job started: deploy (in_progress)"),
        (14, "Job deploy: running — Provision vCluster"),
        (22, "Job deploy: running — Helm sync"),
        (32, "Job deploy: success"),
        (34, "GitHub Actions workflow completed successfully"),
    ]
    dep = store.get(dep_id)
    if dep is None:
        yield _sse({"type": "error", "message": "Deployment not found"})
        return

    dep.run_url = dep.run_url or "https://github.com/actions"
    store.update(dep)
    sent = 0
    while not _is_terminal(dep):
        seconds = (_now() - dep.created_at).total_seconds()
        while sent < len(timeline) and timeline[sent][0] <= seconds:
            line = timeline[sent][1]
            store.append_event(dep, line, source="mock")
            if "Helm" in line:
                dep.phase = ClusterPhase.SYNCING
                dep.message = "Syncing the Helm stack"
            elif sent == len(timeline) - 1:
                dep.phase = ClusterPhase.READY
                dep.message = "Stack is ready"
            elif sent < 3:
                dep.phase = ClusterPhase.PROVISIONING
                dep.message = "Workflow run queued on GitHub Actions"
            else:
                dep.phase = ClusterPhase.SYNCING
                dep.message = "Workflow run in progress"
            store.update(dep)
            yield _sse({"type": "log", "line": line, "deployment": dep.to_dict()})
            sent += 1
            if dep.phase == ClusterPhase.READY:
                yield _sse(
                    {
                        "type": "deployment_created",
                        "message": "Deployment created (mock ready)",
                        "deployment": dep.to_dict(),
                        "run_url": dep.run_url,
                    }
                )
        yield _sse({"type": "status", "deployment": dep.to_dict(), "run_url": dep.run_url})
        if _is_terminal(dep):
            break
        await asyncio.sleep(1.5)

    yield _sse({"type": "complete", "deployment": dep.to_dict(), "run_url": dep.run_url})


# Fan out only what the workflow pushes to /api/runner/events (event-driven).
# We do NOT poll GitHub here — that burned the API rate limit. GitHub state is
# fetched on demand (page load / refresh) via /api/clusters, never on a timer.
_STREAM_MAX_LIFETIME_S = 30 * 60
_STREAM_IDLE_TIMEOUT_S = 15 * 60
_HEARTBEAT_EVERY_S = 15.0
_TICK_S = 1.0


async def _runner_tick(dep_id: str, store: DeploymentStore) -> AsyncIterator[str]:
    """Tail runner-callback events from the local store; no GitHub polling."""
    dep = store.get(dep_id)
    if dep is None:
        yield _sse({"type": "error", "message": "Deployment not found"})
        return

    # Replay current state on (re)connect so a refresh mid-deploy shows history.
    seen_keys: set[str] = set()
    last_phase = dep.phase
    for entry in dep.events:
        seen_keys.add(_event_key(entry))
        yield _sse(
            {
                "type": "log",
                "line": entry.get("line"),
                "level": entry.get("level"),
                "source": entry.get("source"),
                "trace_id": entry.get("trace_id") or dep.trace_id,
                "deployment": dep.to_dict(),
                "run_url": dep.run_url,
            }
        )
    yield _sse({"type": "status", "deployment": dep.to_dict(), "run_url": dep.run_url})

    # Reconnect after ready: re-emit the explicit created signal so the UI can settle.
    if dep.phase == ClusterPhase.READY:
        yield _sse(
            {
                "type": "deployment_created",
                "message": "Deployment created (workflow ready signal)",
                "deployment": dep.to_dict(),
                "run_url": dep.run_url,
            }
        )
        yield _sse({"type": "complete", "deployment": dep.to_dict(), "run_url": dep.run_url})
        return

    if dep.phase == ClusterPhase.FAILED:
        yield _sse({"type": "complete", "deployment": dep.to_dict(), "run_url": dep.run_url})
        return

    elapsed = 0.0
    since_event = 0.0
    since_beat = 0.0
    while True:
        await asyncio.sleep(_TICK_S)
        elapsed += _TICK_S
        since_event += _TICK_S
        since_beat += _TICK_S

        dep = store.get(dep_id)
        if dep is None:
            yield _sse({"type": "error", "message": "Deployment not found"})
            return

        emitted = False
        async for chunk in _emit_new_store_events(dep_id, store, seen_keys):
            emitted = True
            yield chunk
        if emitted:
            since_event = 0.0

        # Same signal as Redis lock: workflow phase=ready → UI "deployment created".
        if last_phase != ClusterPhase.READY and dep.phase == ClusterPhase.READY:
            yield _sse(
                {
                    "type": "deployment_created",
                    "message": "Deployment created (workflow ready signal)",
                    "deployment": dep.to_dict(),
                    "run_url": dep.run_url,
                }
            )
        last_phase = dep.phase

        if _is_terminal(dep):
            yield _sse({"type": "complete", "deployment": dep.to_dict(), "run_url": dep.run_url})
            return

        # Keep the SSE connection warm through proxies without any GitHub call.
        if since_beat >= _HEARTBEAT_EVERY_S:
            since_beat = 0.0
            yield ": keepalive\n\n"

        if since_event >= _STREAM_IDLE_TIMEOUT_S or elapsed >= _STREAM_MAX_LIFETIME_S:
            # Stop the open connection; the browser refetches on refresh.
            yield _sse(
                {
                    "type": "idle",
                    "message": "Live stream idle — refresh to fetch latest status.",
                    "deployment": dep.to_dict(),
                    "run_url": dep.run_url,
                }
            )
            return


async def deployment_event_stream(
    dep_id: str,
    gh: GitHubClient | None,
    store: DeploymentStore,
) -> AsyncIterator[str]:
    yield _sse({"type": "connected", "deployment_id": dep_id})
    if gh is None:
        async for chunk in _mock_tick(dep_id, store):
            yield chunk
        return
    async for chunk in _runner_tick(dep_id, store):
        yield chunk
