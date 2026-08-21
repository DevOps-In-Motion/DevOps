"""SQLite-backed deployment store (PVC-mounted path in cluster)."""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from threading import Lock
from uuid import uuid4

MAX_EVENTS = 200

# Active phases that block a duplicate deploy for the same vcluster_name
ACTIVE_PHASES = frozenset({"provisioning", "syncing"})

# Lifecycle overlays the GitHub-run phase.
#   active     — current attempt for this vCluster (shown in Active/Failed by phase).
#   deleting   — deletion event arrived; kept shown until re-verified.
#   deleted    — teardown confirmed; hidden.
#   superseded — a newer deploy for the same vCluster replaced this attempt; hidden.
# One *visible* attempt per vcluster_name: create() supersedes priors.
LIFECYCLE_ACTIVE = "active"
LIFECYCLE_DELETING = "deleting"
LIFECYCLE_DELETED = "deleted"
LIFECYCLE_SUPERSEDED = "superseded"
VALID_LIFECYCLE = frozenset(
    {LIFECYCLE_ACTIVE, LIFECYCLE_DELETING, LIFECYCLE_DELETED, LIFECYCLE_SUPERSEDED}
)


class ClusterPhase(str, Enum):
    PROVISIONING = "provisioning"
    SYNCING = "syncing"
    READY = "ready"
    FAILED = "failed"


def _now() -> datetime:
    return datetime.now(timezone.utc)


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


class ClusterDeployment:
    __slots__ = (
        "id",
        "repo",
        "branch",
        "workflow",
        "ttl",
        "reason",
        "linear_ticket",
        "dispatch_repo",
        "dispatch_ref",
        "vcluster_name",
        "phase",
        "created_at",
        "message",
        "run_id",
        "run_url",
        "run_status",
        "run_conclusion",
        "jobs",
        "events",
        "trace_id",
        "lifecycle",
        "delete_requested_at",
    )

    def __init__(
        self,
        *,
        id: str,
        repo: str,
        branch: str,
        workflow: str,
        ttl: str,
        reason: str,
        linear_ticket: str,
        dispatch_repo: str = "",
        dispatch_ref: str = "main",
        vcluster_name: str = "",
        phase: ClusterPhase = ClusterPhase.PROVISIONING,
        created_at: datetime | None = None,
        message: str = "Deployment requested",
        run_id: int | None = None,
        run_url: str | None = None,
        run_status: str | None = None,
        run_conclusion: str | None = None,
        jobs: list[dict] | None = None,
        events: list[dict] | None = None,
        trace_id: str = "",
        lifecycle: str = LIFECYCLE_ACTIVE,
        delete_requested_at: datetime | None = None,
    ) -> None:
        self.id = id
        self.repo = repo
        self.branch = branch
        self.workflow = workflow
        self.ttl = ttl
        self.reason = reason
        self.linear_ticket = linear_ticket
        self.dispatch_repo = dispatch_repo or repo
        self.dispatch_ref = dispatch_ref or "main"
        self.vcluster_name = vcluster_name
        self.phase = phase
        self.created_at = created_at or _now()
        self.message = message
        self.run_id = run_id
        self.run_url = run_url
        self.run_status = run_status
        self.run_conclusion = run_conclusion
        self.jobs = jobs or []
        self.events = events or []
        self.trace_id = trace_id or ""
        self.lifecycle = lifecycle if lifecycle in VALID_LIFECYCLE else LIFECYCLE_ACTIVE
        self.delete_requested_at = delete_requested_at

    def is_visible(self) -> bool:
        """Shown in the deployments list: pipeline finished + deployed, not torn down."""
        if self.lifecycle in (LIFECYCLE_DELETED, LIFECYCLE_SUPERSEDED):
            return False
        phase = self.phase if isinstance(self.phase, ClusterPhase) else ClusterPhase(self.phase)
        return phase == ClusterPhase.READY

    def actions_repo(self) -> str:
        return (self.dispatch_repo or self.repo).strip()

    def actions_ref(self) -> str:
        return (self.dispatch_ref or self.branch or "main").strip()

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "repo": self.repo,
            "branch": self.branch,
            "workflow": self.workflow,
            "ttl": self.ttl,
            "reason": self.reason,
            "linear_ticket": self.linear_ticket,
            "dispatch_repo": self.dispatch_repo or self.repo,
            "dispatch_ref": self.dispatch_ref or "main",
            "vcluster_name": self.vcluster_name,
            "phase": self.phase.value if isinstance(self.phase, ClusterPhase) else self.phase,
            "status_label": _phase_label(
                self.phase if isinstance(self.phase, ClusterPhase) else ClusterPhase(self.phase)
            ),
            "created_at": self.created_at.isoformat(),
            "message": self.message,
            "run_id": self.run_id,
            "run_url": self.run_url,
            "run_status": self.run_status,
            "run_conclusion": self.run_conclusion,
            "jobs": self.jobs,
            "events": self.events[-50:],
            "trace_id": self.trace_id,
            "lifecycle": self.lifecycle,
            "delete_requested_at": (
                self.delete_requested_at.isoformat() if self.delete_requested_at else None
            ),
            "visible": self.is_visible(),
        }

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> ClusterDeployment:
        data = json.loads(row["payload"])
        phase = data.get("phase", ClusterPhase.PROVISIONING.value)
        created = data.get("created_at")
        deleted_req = data.get("delete_requested_at")
        return cls(
            id=data["id"],
            repo=data["repo"],
            branch=data["branch"],
            workflow=data["workflow"],
            ttl=data.get("ttl") or "",
            reason=data.get("reason") or "",
            linear_ticket=data.get("linear_ticket") or "",
            dispatch_repo=data.get("dispatch_repo") or "",
            dispatch_ref=data.get("dispatch_ref") or "main",
            vcluster_name=data.get("vcluster_name") or "",
            phase=ClusterPhase(phase),
            created_at=datetime.fromisoformat(created) if created else _now(),
            message=data.get("message") or "",
            run_id=data.get("run_id"),
            run_url=data.get("run_url"),
            run_status=data.get("run_status"),
            run_conclusion=data.get("run_conclusion"),
            jobs=data.get("jobs") or [],
            events=data.get("events") or [],
            trace_id=data.get("trace_id") or "",
            lifecycle=data.get("lifecycle") or LIFECYCLE_ACTIVE,
            delete_requested_at=datetime.fromisoformat(deleted_req) if deleted_req else None,
        )

    def payload_json(self) -> str:
        """Serialize domain state for the payload column (no derived UI fields)."""
        d = self.to_dict()
        d.pop("status_label", None)  # computed on read via to_dict()
        d.pop("visible", None)  # derived from phase + lifecycle
        d["events"] = self.events[-MAX_EVENTS:]
        d["jobs"] = self.jobs
        return json.dumps(d)


class DeploymentStore:
    """SQLite journal of UAT deploys.

    Schema is a hybrid document store:
      - Columns id / vcluster_name / phase / created_at — indexed query keys
        (conflict checks, sort). Always written from the same ClusterDeployment.
      - Column payload — full JSON document (API + SSE state). Reads hydrate
        from payload only; never treat columns as a second source of truth for
        fields other than query filters.
    """

    def __init__(self, db_path: str | Path) -> None:
        self._path = Path(db_path)
        self._lock = Lock()
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self._path), check_same_thread=False, timeout=30)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=30000")
        return conn

    def _init_db(self) -> None:
        with self._lock:
            conn = self._connect()
            try:
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS deployments (
                        id TEXT PRIMARY KEY,
                        vcluster_name TEXT NOT NULL DEFAULT '',
                        phase TEXT NOT NULL
                            CHECK (phase IN ('provisioning', 'syncing', 'ready', 'failed')),
                        created_at TEXT NOT NULL,
                        payload TEXT NOT NULL
                    )
                    """
                )
                # ISO-8601 created_at sorts lexicographically as time order.
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_deployments_created ON deployments(created_at DESC)"
                )
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_deployments_vcluster_phase "
                    "ON deployments(vcluster_name, phase, created_at DESC)"
                )
                conn.commit()
            finally:
                conn.close()

    def create(
        self,
        *,
        repo: str,
        branch: str,
        workflow: str,
        ttl: str,
        reason: str,
        linear_ticket: str,
        dispatch_repo: str = "",
        dispatch_ref: str = "main",
        vcluster_name: str = "",
        trace_id: str = "",
        id: str | None = None,
    ) -> ClusterDeployment:
        dep = ClusterDeployment(
            id=(id or uuid4().hex[:12]),
            repo=repo,
            branch=branch,
            workflow=workflow,
            ttl=ttl,
            reason=reason,
            linear_ticket=linear_ticket,
            dispatch_repo=dispatch_repo or repo,
            dispatch_ref=dispatch_ref or "main",
            vcluster_name=vcluster_name,
            trace_id=trace_id,
        )
        self.update(dep)
        return dep

    def supersede_prior_for_vcluster(
        self,
        vcluster_name: str,
        *,
        keep_id: str,
        reason: str = "Superseded by a newer deploy for this environment",
    ) -> int:
        """Supersede prior in-flight/ready attempts for this vCluster.

        Failed rows stay visible so the Failed tab can groupby repo@branch history.
        """
        name = (vcluster_name or "").strip()
        if not name:
            return 0
        n = 0
        for dep in self.list_recent(200):
            if dep.vcluster_name != name:
                continue
            if dep.id == keep_id:
                continue
            if dep.lifecycle in (LIFECYCLE_DELETED, LIFECYCLE_SUPERSEDED):
                continue
            phase = (
                dep.phase
                if isinstance(dep.phase, ClusterPhase)
                else ClusterPhase(dep.phase)
            )
            if phase == ClusterPhase.FAILED:
                continue
            dep.lifecycle = LIFECYCLE_SUPERSEDED
            self.append_event(dep, reason, source="system")
            n += 1
        return n

    def list_recent(self, limit: int = 20) -> list[ClusterDeployment]:
        with self._lock:
            conn = self._connect()
            try:
                rows = conn.execute(
                    "SELECT payload FROM deployments ORDER BY created_at DESC LIMIT ?",
                    (limit,),
                ).fetchall()
                return [ClusterDeployment.from_row(r) for r in rows]
            finally:
                conn.close()

    def get(self, deployment_id: str) -> ClusterDeployment | None:
        with self._lock:
            conn = self._connect()
            try:
                row = conn.execute(
                    "SELECT payload FROM deployments WHERE id = ?",
                    (deployment_id,),
                ).fetchone()
                if row is None:
                    return None
                return ClusterDeployment.from_row(row)
            finally:
                conn.close()

    def find_active_by_vcluster(self, vcluster_name: str) -> ClusterDeployment | None:
        """Return newest deploy still provisioning/syncing for this vCluster name."""
        if not vcluster_name:
            return None
        active = tuple(sorted(ACTIVE_PHASES))
        with self._lock:
            conn = self._connect()
            try:
                rows = conn.execute(
                    """
                    SELECT payload FROM deployments
                    WHERE vcluster_name = ?
                      AND phase IN (?, ?)
                    ORDER BY created_at DESC
                    LIMIT 20
                    """,
                    (vcluster_name, active[0], active[1]),
                ).fetchall()
                for row in rows:
                    dep = ClusterDeployment.from_row(row)
                    if dep.lifecycle in (LIFECYCLE_DELETED, LIFECYCLE_SUPERSEDED):
                        continue
                    return dep
                return None
            finally:
                conn.close()

    def _ready_rows(self, limit: int) -> list[ClusterDeployment]:
        with self._lock:
            conn = self._connect()
            try:
                rows = conn.execute(
                    "SELECT payload FROM deployments WHERE phase = ? "
                    "ORDER BY created_at DESC LIMIT ?",
                    (ClusterPhase.READY.value, limit),
                ).fetchall()
                return [ClusterDeployment.from_row(r) for r in rows]
            finally:
                conn.close()

    def list_visible(self, limit: int = 50) -> list[ClusterDeployment]:
        """Deployments to show: pipeline finished + deployed (ready), not torn down.

        ``deleting`` rows stay visible until re-verification flips them to
        ``deleted`` (hidden) or back to ``active``.
        """
        # Over-fetch so confirmed-deleted ready rows don't crowd out the window.
        rows = self._ready_rows(max(limit * 4, limit))
        visible = [d for d in rows if d.lifecycle != LIFECYCLE_DELETED]
        return visible[:limit]

    def list_history(self, limit: int = 50) -> list[ClusterDeployment]:
        """UI history: current Active attempts + Failed history (never starved).

        Active: provisioning/syncing/ready with lifecycle not deleted/superseded.
        Failed: phase=failed, not deleted — **superseded failed rows still count**
        so the Failed tab can groupby repo@branch across retries.
        """
        hide_active = {LIFECYCLE_DELETED, LIFECYCLE_SUPERSEDED}
        rows = self.list_recent(max(limit * 4, 200))
        activeish: list[ClusterDeployment] = []
        for dep in rows:
            if dep.lifecycle in hide_active:
                continue
            phase = (
                dep.phase
                if isinstance(dep.phase, ClusterPhase)
                else ClusterPhase(dep.phase)
            )
            if phase in (
                ClusterPhase.PROVISIONING,
                ClusterPhase.SYNCING,
                ClusterPhase.READY,
            ):
                activeish.append(dep)
            if len(activeish) >= limit:
                break

        failed: list[ClusterDeployment] = []
        for dep in self._rows_by_phase(ClusterPhase.FAILED.value, limit * 2):
            if dep.lifecycle == LIFECYCLE_DELETED:
                continue
            failed.append(dep)
            if len(failed) >= limit:
                break

        return activeish + failed

    def _rows_by_phase(self, phase: str, limit: int) -> list[ClusterDeployment]:
        with self._lock:
            conn = self._connect()
            try:
                rows = conn.execute(
                    "SELECT payload FROM deployments WHERE phase = ? "
                    "ORDER BY created_at DESC LIMIT ?",
                    (phase, limit),
                ).fetchall()
                return [ClusterDeployment.from_row(r) for r in rows]
            finally:
                conn.close()

    def list_deleting(self, limit: int = 200) -> list[ClusterDeployment]:
        """Ready rows awaiting deletion verification (used to resume on startup)."""
        return [d for d in self._ready_rows(limit) if d.lifecycle == LIFECYCLE_DELETING]

    def find_visible_by_vcluster(self, vcluster_name: str) -> ClusterDeployment | None:
        """Newest still-visible (ready, not deleted) deployment for a vCluster name."""
        if not vcluster_name:
            return None
        for dep in self._ready_rows(200):
            if dep.vcluster_name == vcluster_name and dep.lifecycle not in (
                LIFECYCLE_DELETED,
                LIFECYCLE_SUPERSEDED,
            ):
                return dep
        return None

    def mark_deleting(self, dep: ClusterDeployment, message: str | None = None) -> ClusterDeployment:
        dep.lifecycle = LIFECYCLE_DELETING
        dep.delete_requested_at = _now()
        self.append_event(
            dep,
            message or "Deletion event received — verifying teardown",
            source="system",
        )
        return dep

    def mark_deleted(self, dep: ClusterDeployment, message: str | None = None) -> ClusterDeployment:
        dep.lifecycle = LIFECYCLE_DELETED
        self.append_event(
            dep,
            message or "Deletion confirmed — removed from active deployments",
            source="system",
        )
        return dep

    def mark_active(self, dep: ClusterDeployment, message: str | None = None) -> ClusterDeployment:
        dep.lifecycle = LIFECYCLE_ACTIVE
        dep.delete_requested_at = None
        self.append_event(
            dep,
            message or "Deployment still live — kept active",
            level="warn",
            source="system",
        )
        return dep

    def update(self, dep: ClusterDeployment) -> None:
        phase = dep.phase.value if isinstance(dep.phase, ClusterPhase) else str(dep.phase)
        if phase not in ACTIVE_PHASES | {"ready", "failed"}:
            raise ValueError(f"invalid deployment phase: {phase!r}")
        with self._lock:
            conn = self._connect()
            try:
                conn.execute(
                    """
                    INSERT INTO deployments (id, vcluster_name, phase, created_at, payload)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        vcluster_name = excluded.vcluster_name,
                        phase = excluded.phase,
                        payload = excluded.payload
                    """,
                    (
                        dep.id,
                        dep.vcluster_name or "",
                        phase,
                        dep.created_at.isoformat(),
                        dep.payload_json(),
                    ),
                )
                conn.commit()
            finally:
                conn.close()

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
        if dep.trace_id:
            entry["trace_id"] = dep.trace_id
        dep.events.append(entry)
        if len(dep.events) > MAX_EVENTS:
            dep.events = dep.events[-MAX_EVENTS:]
        self.update(dep)
        return entry

    def apply_github_snapshot(self, dep: ClusterDeployment, snapshot: dict) -> list[str]:
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
        """Dev/mock timeline helper only.

        Never advances to ``ready`` — that is event-driven from the workflow
        (``POST /api/runner/events`` with ``phase=ready``). Auto-ready here is
        what made incomplete deploys show as success in the UI.
        """
        if dep.run_id is not None:
            return dep
        if dep.phase in (ClusterPhase.READY, ClusterPhase.FAILED):
            return dep
        elapsed = (_now() - dep.created_at).total_seconds()
        if elapsed < 20:
            dep.phase = ClusterPhase.PROVISIONING
            dep.message = "Provisioning the cluster control plane"
        else:
            dep.phase = ClusterPhase.SYNCING
            dep.message = "Waiting for workflow ready signal"
        self.update(dep)
        return dep
