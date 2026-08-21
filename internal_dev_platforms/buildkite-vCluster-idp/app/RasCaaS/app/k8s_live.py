"""List live vClusters on the host cluster (in-cluster kubeconfig).

UAT rule: one virtual cluster per namespace. Identity is ``tmp-<repo>-<branch>``
for both the host namespace and the Helm release name (vCluster ≥0.25).
Legacy shared namespace ``vcluster`` and older ``vcluster-*`` names are still scanned.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)

LEGACY_HOST_NAMESPACE = "vcluster"
UAT_NS_LABEL = "app.kubernetes.io/part-of=rascaas-uat"


def _is_uat_vcluster_name(name: str) -> bool:
    """UAT release names: tmp-<repo>-<branch> (legacy vcluster-*)."""
    return name.startswith("tmp-") or name.startswith("vcluster-")


def _kube_clients():
    try:
        from kubernetes import client, config
    except ImportError:
        logger.warning("kubernetes package not installed — live listing disabled")
        return None, None, None

    try:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
    except Exception as exc:
        logger.info("No kubeconfig for live listing: %s", exc)
        return None, None, None

    return client.AppsV1Api(), client.CoreV1Api(), client


def _ready_replicas(item: Any) -> bool | None:
    status = getattr(item, "status", None)
    if status is None:
        return None
    ready = getattr(status, "ready_replicas", None)
    replicas = getattr(status, "replicas", None)
    if ready is None and replicas is None:
        return None
    return bool(ready) and ready == (replicas or 0)


def list_live_vclusters(host_namespace: str = LEGACY_HOST_NAMESPACE) -> list[dict[str, Any]]:
    """
    Return Helm releases / StatefulSets that look like vClusters in host_namespace.
    Empty list if not running in-cluster or RBAC denied.
    """
    apps, core, _client = _kube_clients()
    if apps is None or core is None:
        return []

    out: list[dict[str, Any]] = []
    seen: set[str] = set()

    try:
        sts = apps.list_namespaced_stateful_set(host_namespace)
        for item in sts.items:
            name = item.metadata.name
            labels = item.metadata.labels or {}
            # vCluster control plane commonly labeled app=vcluster / release=<name>
            if labels.get("app") == "vcluster" or _is_uat_vcluster_name(name):
                seen.add(name)
                out.append(
                    {
                        "name": name,
                        "namespace": host_namespace,
                        "kind": "StatefulSet",
                        "ready": _ready_replicas(item),
                        "labels": labels,
                    }
                )
    except Exception as exc:
        logger.warning("list StatefulSet failed ns=%s: %s", host_namespace, exc)

    try:
        deps = apps.list_namespaced_deployment(host_namespace)
        for item in deps.items:
            name = item.metadata.name
            if name in seen:
                continue
            labels = item.metadata.labels or {}
            if labels.get("app") == "vcluster" or _is_uat_vcluster_name(name):
                seen.add(name)
                out.append(
                    {
                        "name": name,
                        "namespace": host_namespace,
                        "kind": "Deployment",
                        "ready": _ready_replicas(item),
                        "labels": labels,
                    }
                )
    except Exception as exc:
        logger.warning("list Deployment failed ns=%s: %s", host_namespace, exc)

    # Helm release secrets (backup signal)
    try:
        secrets = core.list_namespaced_secret(host_namespace, label_selector="owner=helm")
        for sec in secrets.items:
            # sh.helm.release.v1.<name>.v<N>
            meta_name = sec.metadata.name or ""
            if not meta_name.startswith("sh.helm.release.v1."):
                continue
            release = meta_name[len("sh.helm.release.v1.") :].rsplit(".v", 1)[0]
            if release in seen:
                continue
            label_name = (sec.metadata.labels or {}).get("name", "")
            if _is_uat_vcluster_name(release) or _is_uat_vcluster_name(label_name):
                seen.add(release)
                out.append(
                    {
                        "name": release,
                        "namespace": host_namespace,
                        "kind": "HelmRelease",
                        "ready": None,
                        "labels": sec.metadata.labels or {},
                    }
                )
    except Exception as exc:
        logger.debug("list helm secrets skipped ns=%s: %s", host_namespace, exc)

    out.sort(key=lambda x: x["name"])
    return out


def _candidate_host_namespaces(
    vcluster_name: str = "",
    configured_legacy: str = LEGACY_HOST_NAMESPACE,
) -> list[str]:
    """Namespaces to search: dedicated (name), labeled UAT ns, legacy shared."""
    ordered: list[str] = []
    seen: set[str] = set()

    def add(ns: str) -> None:
        ns = (ns or "").strip()
        if not ns or ns in seen:
            return
        seen.add(ns)
        ordered.append(ns)

    add(vcluster_name)  # dedicated ns == vcluster name (new default)
    add(configured_legacy)

    _apps, core, _client = _kube_clients()
    if core is not None:
        try:
            for item in core.list_namespace(label_selector=UAT_NS_LABEL).items:
                add(item.metadata.name)
        except Exception as exc:
            logger.debug("list UAT namespaces skipped: %s", exc)

    return ordered


def list_all_live_vclusters(
    legacy_host_namespace: str = LEGACY_HOST_NAMESPACE,
) -> list[dict[str, Any]]:
    """Scan dedicated + legacy host namespaces for UAT vClusters."""
    by_name: dict[str, dict[str, Any]] = {}
    for ns in _candidate_host_namespaces(configured_legacy=legacy_host_namespace):
        for row in list_live_vclusters(ns):
            by_name[row["name"]] = row
    return sorted(by_name.values(), key=lambda x: x["name"])


def vcluster_exists(name: str, host_namespace: str = LEGACY_HOST_NAMESPACE) -> bool:
    """True if a vCluster Helm/control-plane object exists under this name.

    Checks the dedicated namespace (``name``), then ``host_namespace`` / labeled
    UAT namespaces (legacy shared ``vcluster`` included).
    """
    if not name:
        return False
    for ns in _candidate_host_namespaces(name, configured_legacy=host_namespace):
        if any(v["name"] == name for v in list_live_vclusters(ns)):
            return True
    return False
