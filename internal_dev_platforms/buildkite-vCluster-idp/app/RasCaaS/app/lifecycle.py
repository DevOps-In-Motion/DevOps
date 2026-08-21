"""Event-driven deletion verification for UAT deployments.

A deleter (TTL cleanup Job, manual teardown) POSTs to ``/api/runner/deleted``
when it tears a vCluster down. We mark the deployment ``deleting`` (still shown),
then re-check the cluster after ``delete_verify_delay_s``:

  - confirmed gone  → ``deleted`` (hidden from the deployments list)
  - still live      → back to ``active`` (kept in the list)

No polling: the event is the trigger and the single follow-up check is the only
cluster read. Verification tasks are in-memory; :func:`reconcile_pending_deletions`
resumes any that were mid-flight when the pod restarted.
"""

from __future__ import annotations

import asyncio

from app.deployments import LIFECYCLE_DELETING, DeploymentStore, _now
from app.k8s_live import vcluster_exists
from app.logging_config import get_logger
from app.tracing import deployment_context

log = get_logger("rascaas.lifecycle")

# Hold task refs so the event loop does not garbage-collect them mid-flight.
_tasks: set[asyncio.Task] = set()


async def _verify(store: DeploymentStore, dep_id: str, host_namespace: str, delay_s: float) -> None:
    try:
        if delay_s > 0:
            await asyncio.sleep(delay_s)

        dep = store.get(dep_id)
        if dep is None or dep.lifecycle != LIFECYCLE_DELETING:
            return  # gone, re-deployed, or already resolved

        name = dep.vcluster_name
        still_live = False
        if name:
            # kubernetes client is sync — keep it off the event loop.
            still_live = await asyncio.to_thread(vcluster_exists, name, host_namespace)

        dep = store.get(dep_id)  # re-read: state may have changed during the check
        if dep is None or dep.lifecycle != LIFECYCLE_DELETING:
            return

        with deployment_context(dep.id, dep.trace_id or None):
            if still_live:
                store.mark_active(
                    dep,
                    f"Deletion not confirmed after {int(delay_s)}s — {name} still live; keeping active",
                )
                log.warning(
                    "deletion unconfirmed deployment_id=%s vcluster=%s — kept active",
                    dep.id,
                    name,
                    extra={
                        "event": "deletion_unconfirmed",
                        "deployment_id": dep.id,
                        "vcluster": name,
                        "trace_id": dep.trace_id,
                    },
                )
            else:
                store.mark_deleted(dep)
                if name:
                    from app.locks import get_lock_store

                    # Teardown ends the live env hold; also clear leftover inflight.
                    await get_lock_store().release(name, dep.id)
                log.info(
                    "deletion confirmed deployment_id=%s vcluster=%s — hidden",
                    dep.id,
                    name,
                    extra={
                        "event": "deletion_confirmed",
                        "deployment_id": dep.id,
                        "vcluster": name,
                        "trace_id": dep.trace_id,
                    },
                )
    except asyncio.CancelledError:
        raise
    except Exception:
        log.exception("deletion verification failed deployment_id=%s", dep_id)


def schedule_deletion_verification(
    store: DeploymentStore,
    dep_id: str,
    host_namespace: str,
    delay_s: float,
) -> asyncio.Task:
    task = asyncio.create_task(_verify(store, dep_id, host_namespace, delay_s))
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)
    return task


async def reconcile_pending_deletions(
    store: DeploymentStore,
    host_namespace: str,
    delay_s: float,
) -> None:
    """Resume verification for deployments left in ``deleting`` (e.g. after restart)."""
    for dep in store.list_deleting():
        remaining = delay_s
        if dep.delete_requested_at is not None:
            elapsed = (_now() - dep.delete_requested_at).total_seconds()
            remaining = max(0.0, delay_s - elapsed)
        schedule_deletion_verification(store, dep.id, host_namespace, remaining)
        log.info(
            "resumed deletion verification deployment_id=%s in %ss",
            dep.id,
            int(remaining),
            extra={
                "event": "deletion_verify_resumed",
                "deployment_id": dep.id,
                "trace_id": dep.trace_id,
            },
        )
