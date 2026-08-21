"""Active/Failed status partition + repo@branch groupby smoke test."""

from __future__ import annotations

import logging
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

_fake_log = types.ModuleType("app.logging_config")
_fake_log.get_logger = lambda name: logging.getLogger(name)  # type: ignore[attr-defined]
sys.modules["app.logging_config"] = _fake_log

from app.deployments import (  # noqa: E402
    LIFECYCLE_SUPERSEDED,
    ClusterDeployment,
    ClusterPhase,
)
from app.history_groups import build_history_groups  # noqa: E402


def _dep(**kw) -> ClusterDeployment:
    d = ClusterDeployment(
        id=kw["id"],
        repo=kw.get("repo", "kovr-ai/a"),
        branch=kw.get("branch", "main"),
        workflow="uat-deploy.yml",
        ttl="3d",
        reason="",
        linear_ticket="",
        phase=kw["phase"],
    )
    if kw.get("lifecycle"):
        d.lifecycle = kw["lifecycle"]
    return d


def main() -> None:
    rows = [
        _dep(id="f1", repo="kovr-ai/a", branch="main", phase=ClusterPhase.FAILED),
        _dep(id="f2", repo="kovr-ai/a", branch="main", phase=ClusterPhase.FAILED),
        _dep(
            id="f3",
            repo="kovr-ai/a",
            branch="main",
            phase=ClusterPhase.FAILED,
            lifecycle=LIFECYCLE_SUPERSEDED,  # must still appear on Failed
        ),
        _dep(id="r1", repo="kovr-ai/a", branch="main", phase=ClusterPhase.READY),
        _dep(id="p1", repo="kovr-ai/b", branch="feat", phase=ClusterPhase.PROVISIONING),
        _dep(
            id="old",
            repo="kovr-ai/b",
            branch="feat",
            phase=ClusterPhase.READY,
            lifecycle=LIFECYCLE_SUPERSEDED,  # must NOT appear on Active
        ),
    ]
    out = build_history_groups(rows)

    assert len(out["failed"]) == 1, out["failed"]
    assert out["failed"][0]["label"] == "kovr-ai/a @ main"
    assert out["failed"][0]["count"] == 3
    failed_ids = {d["id"] for d in out["failed"][0]["deployments"]}
    assert failed_ids == {"f1", "f2", "f3"}

    active_labels = {g["label"] for g in out["active"]}
    assert active_labels == {"kovr-ai/a @ main", "kovr-ai/b @ feat"}, active_labels
    active_ids = {d["id"] for g in out["active"] for d in g["deployments"]}
    assert active_ids == {"r1", "p1"}, active_ids
    assert all(d["phase"] != "failed" for g in out["active"] for d in g["deployments"])
    assert all(d["phase"] == "failed" for g in out["failed"] for d in g["deployments"])

    print("history_groups status+repo groupby: ok")


if __name__ == "__main__":
    main()
