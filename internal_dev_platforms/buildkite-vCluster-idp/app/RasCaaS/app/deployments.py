"""In-memory cluster deployment tracker (replace with vCluster API when wired)."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from threading import Lock
from typing import Any
from uuid import uuid4

MAX_EVENTS = 200


class ClusterPhase(str, Enum):
    PROVISIONING = "provisioning"
    SYNCING = "syncing"
    READY = "ready"
    FAILED = "failed"


def _now() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class ClusterDeployment:
    id: str
    repo: str
    branch: str
    workflow: str
    ttl: str
    reason: str
    linear_ticket: str
    phase: ClusterPhase = ClusterPhase.PROVISIONING
    created_at: datetime = field(default_factory=_now)
    message: str = "Deployment requested"
    run_id: int | None = None
    run_url: str | None = None
    run_status: str | None = None
    run_conclusion: str | None = None
    jobs: list[dict] = field(default_factory=list)
    events: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "repo": self.repo,
            "branch": self.branch,
            "workflow": self.workflow,
            "ttl": self.ttl,
            "reason": self.reason,
            "linear_ticket": self.linear_ticket,
            "phase": self.phase.value,
            "status_label": _phase_label(self.phase),
            "created_at": self.created_at.isoformat(),
            "message": self.message,
            "run_id": self.run_id,
            "run_url": self.run_url,
            "run_status": self.run_status,
            "run_conclusion": self.run_conclusion,
            "jobs": self.jobs,
            "events": self.events[-50:],
        }


def _phase_label(phase: ClusterPhase) -> str:
    return {
        ClusterPhase.PROVISIONING: "Provisioning",
        ClusterPhase.SYNCING: "Syncing",
        ClusterPhase.READY: "Ready",
        ClusterPhase.FAILED: "Failed",
    }[phase]


def phase_from_github_run(status: str | None, conclusion: str | None) -> ClusterPhase:
    if status in (None, "queued", "waiting", "requested", "pending"):
        return ClusterPhase.PROVISIONING
    if status == "in_progress":
        return ClusterPhase.SYNCING
    if status == "completed":
        if conclusion == "success":
            return ClusterPhase.READY
        return ClusterPhase.FAILED
    return ClusterPhase.SYNCING


def message_from_github_run(status: str | None, conclusion: str | None) -> str:
    if status in ("queued", "waiting", "requested", "pending"):
        return "Workflow run queued on GitHub Actions"
    if status == "in_progress":
        return "Workflow run in progress"
    if status == "completed":
        if conclusion == "success":
            return "GitHub Actions workflow completed successfully"
        if conclusion == "failure":
            return "GitHub Actions workflow failed"
        if conclusion == "cancelled":
            return "GitHub Actions workflow was cancelled"
        return f"GitHub Actions workflow completed ({conclusion or 'unknown'})"
    return "Polling GitHub Actions"


class DeploymentStore:
    def __init__(self) -> None:
        self._items: dict[str, ClusterDeployment] = {}
        self._lock = Lock()

    def create(
        self,
        *,
        repo: str,
        branch: str,
        workflow: str,
        ttl: str,
        reason: str,
        linear_ticket: str,
    ) -> ClusterDeployment:
        dep = ClusterDeployment(
            id=uuid4().hex[:12],
            repo=repo,
            branch=branch,
            workflow=workflow,
            ttl=ttl,
            reason=reason,
            linear_ticket=linear_ticket,
        )
        with self._lock:
            self._items[dep.id] = dep
        return dep

    def list_recent(self, limit: int = 20) -> list[ClusterDeployment]:
        with self._lock:
            items = list(self._items.values())
        items.sort(key=lambda d: d.created_at, reverse=True)
        return items[:limit]

    def get(self, deployment_id: str) -> ClusterDeployment | None:
        with self._lock:
            item = self._items.get(deployment_id)
            if item is None:
                return None
            return item

    def update(self, dep: ClusterDeployment) -> None:
        with self._lock:
            self._items[dep.id] = dep

    def append_event(
        self,
        dep: ClusterDeployment,
        line: str,
        *,
        level: str = "info",
        source: str = "system",
    ) -> dict:
        entry = {
            "ts": _now().isoformat(),
            "line": line,
            "level": level,
            "source": source,
        }
        with self._lock:
            dep.events.append(entry)
            if len(dep.events) > MAX_EVENTS:
                dep.events = dep.events[-MAX_EVENTS:]
        return entry

    def apply_github_snapshot(self, dep: ClusterDeployment, snapshot: dict) -> list[str]:
        """Update deployment from GitHub poll; return new log lines."""
        new_lines: list[str] = []
        prev_jobs = {j["id"]: j for j in dep.jobs if j.get("id") is not None}

        if snapshot.get("run_id") and dep.run_id != snapshot["run_id"]:
            dep.run_id = snapshot["run_id"]
            dep.run_url = snapshot.get("run_url")
            new_lines.append(f"GitHub Actions run #{dep.run_id} created")

        dep.run_url = snapshot.get("run_url") or dep.run_url
        dep.run_status = snapshot.get("status")
        dep.run_conclusion = snapshot.get("conclusion")
        dep.jobs = snapshot.get("jobs", [])

        status = snapshot.get("status")
        conclusion = snapshot.get("conclusion")
        dep.phase = phase_from_github_run(status, conclusion)
        dep.message = message_from_github_run(status, conclusion)

        for job in dep.jobs:
            jid = job.get("id")
            name = job.get("name") or "job"
            status = job.get("status")
            conclusion = job.get("conclusion")
            prev = prev_jobs.get(jid)
            if prev is None:
                new_lines.append(f"Job started: {name} ({status})")
            elif prev.get("status") != status or prev.get("conclusion") != conclusion:
                if status == "completed":
                    new_lines.append(f"Job {name}: {conclusion or status}")
                else:
                    new_lines.append(f"Job {name}: {status}")

        for line in new_lines:
            level = "error" if "fail" in line.lower() else "info"
            self.append_event(dep, line, level=level, source="github")

        self.update(dep)
        return new_lines

    def refresh_phase(self, dep: ClusterDeployment) -> ClusterDeployment:
        """Mock lifecycle when GitHub is not linked (no run_id)."""
        if dep.run_id is not None:
            return dep
        if dep.phase in (ClusterPhase.READY, ClusterPhase.FAILED):
            return dep
        elapsed = (_now() - dep.created_at).total_seconds()
        if elapsed < 20:
            dep.phase = ClusterPhase.PROVISIONING
            dep.message = "Provisioning the cluster control plane"
        elif elapsed < 50:
            dep.phase = ClusterPhase.SYNCING
            dep.message = "Syncing the Kovr.ai Helm stack"
        else:
            dep.phase = ClusterPhase.READY
            dep.message = "Stack is ready in QA"
        self.update(dep)
        return dep


store = DeploymentStore()
