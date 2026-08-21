"""History tabs: partition by phase (status), then groupby (repo, branch).

Active tab  → provisioning | syncing | ready  (lifecycle not deleted/superseded)
Failed tab  → phase=failed                 (lifecycle not deleted; superseded OK)

Failed rows must stay visible after a newer deploy supersedes in-flight/ready
attempts — otherwise the Failed tab looks empty / “ungrouped”.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from app.deployments import (
    LIFECYCLE_DELETED,
    LIFECYCLE_SUPERSEDED,
    ClusterDeployment,
    ClusterPhase,
)

_ACTIVE_PHASES = {
    ClusterPhase.READY.value,
    ClusterPhase.PROVISIONING.value,
    ClusterPhase.SYNCING.value,
}


def _phase_value(dep: ClusterDeployment) -> str:
    phase = dep.phase
    # Prefer .value — isinstance(Enum) can fail across duplicate module paths.
    if hasattr(phase, "value"):
        return str(phase.value)
    return str(phase or "")


def _sort_ts(dep_dict: dict[str, Any]) -> float:
    raw = dep_dict.get("created_at") or dep_dict.get("updated_at") or ""
    if isinstance(raw, datetime):
        return raw.timestamp()
    try:
        return datetime.fromisoformat(str(raw).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def _groupby_repo_branch(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """groupby(['repo','branch']) — groups ordered by newest member first."""
    if not rows:
        return []

    ordered = sorted(rows, key=_sort_ts, reverse=True)
    buckets: dict[tuple[str, str], list[dict[str, Any]]] = {}
    order: list[tuple[str, str]] = []
    for row in ordered:
        key = (str(row.get("repo") or ""), str(row.get("branch") or ""))
        if key not in buckets:
            buckets[key] = []
            order.append(key)
        buckets[key].append(row)

    groups: list[dict[str, Any]] = []
    for repo, branch in order:
        deployments = buckets[(repo, branch)]
        groups.append(
            {
                "key": f"{repo}@@{branch}",
                "label": f"{repo} @ {branch}",
                "count": len(deployments),
                "deployments": deployments,
            }
        )
    return groups


def build_history_groups(deps: list[ClusterDeployment]) -> dict[str, list[dict[str, Any]]]:
    """Split by status into Active / Failed tabs, each groupby repo @ branch."""
    active_rows: list[dict[str, Any]] = []
    failed_rows: list[dict[str, Any]] = []

    for dep in deps:
        lifecycle = (dep.lifecycle or "").strip()
        if lifecycle == LIFECYCLE_DELETED:
            continue

        phase = _phase_value(dep)
        row = dep.to_dict()
        row["phase"] = phase

        if phase == ClusterPhase.FAILED.value:
            # Keep failed history even if an older bug marked lifecycle=superseded.
            failed_rows.append(row)
            continue

        if lifecycle == LIFECYCLE_SUPERSEDED:
            continue

        if phase in _ACTIVE_PHASES:
            active_rows.append(row)

    return {
        "active": _groupby_repo_branch(active_rows),
        "failed": _groupby_repo_branch(failed_rows),
    }
