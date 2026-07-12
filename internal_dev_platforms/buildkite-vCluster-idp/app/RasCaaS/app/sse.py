"""Server-Sent Events stream for deployment / GitHub Actions status."""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator
from datetime import timedelta
from typing import TYPE_CHECKING

from app.deployments import ClusterPhase, _now, store

if TYPE_CHECKING:
    from app.github import GitHubClient


def _sse(payload: dict) -> str:
    return f"data: {json.dumps(payload)}\n\n"


def _is_terminal(dep) -> bool:
    return dep.phase in (ClusterPhase.READY, ClusterPhase.FAILED)


async def _mock_tick(dep_id: str) -> AsyncIterator[str]:
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
                dep.message = "Syncing the Kovr.ai Helm stack"
            elif sent == len(timeline) - 1:
                dep.phase = ClusterPhase.READY
                dep.message = "Stack is ready in QA"
            elif sent < 3:
                dep.phase = ClusterPhase.PROVISIONING
                dep.message = "Workflow run queued on GitHub Actions"
            else:
                dep.phase = ClusterPhase.SYNCING
                dep.message = "Workflow run in progress"
            store.update(dep)
            yield _sse({"type": "log", "line": line, "deployment": dep.to_dict()})
            sent += 1
        yield _sse({"type": "status", "deployment": dep.to_dict(), "run_url": dep.run_url})
        if _is_terminal(dep):
            break
        await asyncio.sleep(1.5)

    yield _sse({"type": "complete", "deployment": dep.to_dict(), "run_url": dep.run_url})


async def _github_tick(dep_id: str, gh: GitHubClient) -> AsyncIterator[str]:
    dep = store.get(dep_id)
    if dep is None:
        yield _sse({"type": "error", "message": "Deployment not found"})
        return

    store.append_event(dep, "Connecting to GitHub Actions…", source="system")
    yield _sse({"type": "log", "line": "Connecting to GitHub Actions…", "deployment": dep.to_dict()})

    run = None
    if dep.run_id:
        try:
            run = await gh.get_workflow_run(dep.repo, dep.run_id)
        except Exception as exc:
            store.append_event(dep, f"Could not load run: {exc}", level="error")
            yield _sse({"type": "log", "line": str(exc), "level": "error", "deployment": dep.to_dict()})
    else:
        store.append_event(dep, "Looking for workflow run on GitHub…", source="system")
        yield _sse({"type": "status", "deployment": dep.to_dict()})
        try:
            run = await gh.find_workflow_run(
                dep.repo,
                dep.branch,
                dep.workflow,
                dep.created_at - timedelta(seconds=30),
                attempts=45,
                interval_s=2.0,
            )
        except Exception as exc:
            store.append_event(dep, f"Run lookup failed: {exc}", level="error")
            dep.phase = ClusterPhase.FAILED
            dep.message = "Could not find GitHub Actions run"
            store.update(dep)
            yield _sse({"type": "error", "message": str(exc), "deployment": dep.to_dict()})
            return

    if run is None:
        store.append_event(dep, "Timed out waiting for GitHub Actions run", level="error")
        dep.phase = ClusterPhase.FAILED
        dep.message = "Timed out waiting for GitHub Actions run"
        store.update(dep)
        yield _sse({"type": "complete", "deployment": dep.to_dict()})
        return

    dep.run_id = run["id"]
    dep.run_url = run.get("html_url")
    store.append_event(dep, f"Tracking run #{dep.run_id}", source="github")
    yield _sse(
        {
            "type": "log",
            "line": f"Tracking run #{dep.run_id}",
            "deployment": dep.to_dict(),
            "run_url": dep.run_url,
        }
    )

    while True:
        try:
            run = await gh.get_workflow_run(dep.repo, dep.run_id)
            jobs = await gh.list_workflow_jobs(dep.repo, dep.run_id)
            snapshot = gh.run_snapshot(run, jobs)
            new_lines = store.apply_github_snapshot(dep, snapshot)
            for line in new_lines:
                yield _sse(
                    {
                        "type": "log",
                        "line": line,
                        "deployment": dep.to_dict(),
                        "run_url": dep.run_url,
                    }
                )
            yield _sse(
                {
                    "type": "status",
                    "deployment": dep.to_dict(),
                    "run_url": dep.run_url,
                }
            )
            if _is_terminal(dep):
                yield _sse({"type": "complete", "deployment": dep.to_dict(), "run_url": dep.run_url})
                return
        except Exception as exc:
            store.append_event(dep, f"Poll error: {exc}", level="error")
            yield _sse({"type": "log", "line": str(exc), "level": "error", "deployment": dep.to_dict()})

        await asyncio.sleep(3.0)


async def deployment_event_stream(
    dep_id: str,
    gh: GitHubClient | None,
) -> AsyncIterator[str]:
    yield _sse({"type": "connected", "deployment_id": dep_id})
    if gh is None:
        async for chunk in _mock_tick(dep_id):
            yield chunk
    else:
        async for chunk in _github_tick(dep_id, gh):
            yield chunk
