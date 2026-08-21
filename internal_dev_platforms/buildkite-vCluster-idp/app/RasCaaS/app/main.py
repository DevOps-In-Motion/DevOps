from contextlib import asynccontextmanager
from pathlib import Path
from uuid import uuid4

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

from app.auth import User, get_current_user
from app.config import settings
from app.deployments import ClusterPhase, DeploymentStore
from app.github import GitHubClient, github_api_error_message
from app.history_groups import build_history_groups
from app.k8s_live import list_all_live_vclusters, vcluster_exists
from app.lifecycle import reconcile_pending_deletions
from app.locks import get_lock_store, init_lock_store_from_settings
from app.logging_config import AccessLogMiddleware, get_logger, request_id_ctx, setup_logging
from app.runner_api import router as runner_router
from app.sse import deployment_event_stream
from app.tracing import deployment_context, span, trace_id_ctx

setup_logging(level=settings.log_level, fmt=settings.resolved_log_format)
log = get_logger("rascaas")

APP_DIR = Path(__file__).resolve().parent
TEMPLATE_DIR = APP_DIR / "templates"
STATIC_DIR = APP_DIR / "static"
templates = Jinja2Templates(directory=str(TEMPLATE_DIR))

gh_client: GitHubClient | None = None
store: DeploymentStore | None = None


def _github_configured() -> bool:
    return bool(
        settings.github_app_id
        and settings.github_app_id != "0"
        and settings.github_installation_id
        and settings.github_installation_id != "0"
        and settings.github_private_key
    )


def get_store() -> DeploymentStore:
    assert store is not None
    return store


async def _resolve_workflow(repo: str) -> str:
    if settings.default_workflow:
        return settings.default_workflow
    if gh_client is not None:
        workflows = await gh_client.list_workflows(repo)
        if workflows:
            first = workflows[0]
            return first.get("path") or first.get("id") or first.get("name")
    return "uat-deploy.yml"


@asynccontextmanager
async def lifespan(app: FastAPI):
    global gh_client, store
    log.info(
        "starting RasCaaS env=%s version=%s log_format=%s github=%s",
        settings.environment,
        settings.app_version,
        settings.resolved_log_format,
        "configured" if _github_configured() else "mock",
        extra={"event": "startup"},
    )
    store = DeploymentStore(settings.sqlite_path)
    lock_store = await init_lock_store_from_settings(settings)
    if _github_configured():
        jwt_iss = settings.github_client_id or settings.github_app_id
        gh_client = GitHubClient(
            jwt_iss,
            settings.github_installation_id,
            settings.github_private_key,
        )
        await gh_client.init()
        log.info("GitHub App client ready (dispatch_repo=%s)", settings.github_dispatch_repo or "(selected repo)")
    else:
        log.warning("GitHub App not configured — using mock GitHub API")
    try:
        await reconcile_pending_deletions(
            store, settings.vcluster_host_namespace, settings.delete_verify_delay_s
        )
    except Exception:
        log.exception("failed to resume pending deletion verifications")
    yield
    await lock_store.close()
    if gh_client:
        await gh_client.close()
    log.info("shutdown complete", extra={"event": "shutdown"})


app = FastAPI(lifespan=lifespan)
app.add_middleware(AccessLogMiddleware)
app.include_router(runner_router)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Unexpected errors only (HTTPException uses FastAPI's built-in handler)."""
    rid = request_id_ctx.get()
    log.exception(
        "unhandled exception path=%s",
        request.url.path,
        extra={"event": "unhandled", "method": request.method, "path": request.url.path},
    )
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "request_id": rid,
            "path": request.url.path,
        },
        headers={"X-Request-Id": rid},
    )


if STATIC_DIR.is_dir():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


class DeployRequest(BaseModel):
    repo: str
    branch: str
    ttl: str = "3d"
    reason: str = ""
    linear_ticket: str = ""
    force: bool = False
    # Parent umbrella chart branch on YOUR_ORG/helm-charts.
    helm_charts_branch: str = "main"
    helm_charts_repo: str = "YOUR_ORG/helm-charts"


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/ready")
async def ready():
    try:
        get_store().list_recent(limit=1)
        return {"status": "ready", "sqlite": True}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"sqlite not ready: {exc}") from exc


@app.get("/")
async def index(request: Request):
    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "app_version": settings.app_version,
            "helm_chart_version": settings.helm_chart_version,
            "oidc_logout_url": settings.oidc_logout_url,
        },
    )


@app.get("/api/repos")
async def list_repos(_user: User = Depends(get_current_user)):
    if gh_client is None:
        return [{"full_name": "YOUR_ORG/example", "name": "example"}]
    try:
        return await gh_client.list_repos()
    except Exception as exc:
        detail = github_api_error_message(exc)
        log.exception("GET /api/repos failed: %s", detail)
        raise HTTPException(status_code=502, detail=detail) from exc


@app.get("/api/branches")
async def list_branches(repo: str, _user: User = Depends(get_current_user)):
    if gh_client is None:
        return ["main"]
    try:
        return await gh_client.list_branches(repo)
    except Exception as exc:
        detail = github_api_error_message(exc)
        log.exception("GET /api/branches failed: %s", detail)
        raise HTTPException(status_code=502, detail=detail) from exc


@app.get("/api/version")
async def version_info(_user: User = Depends(get_current_user)):
    return {
        "app_version": settings.app_version,
        "helm_chart_version": settings.helm_chart_version,
    }


@app.get("/api/vclusters")
async def api_list_vclusters(_user: User = Depends(get_current_user)):
    """Live vClusters on the host (Kubernetes API) merged with recent SQLite rows."""
    live = list_all_live_vclusters(settings.vcluster_host_namespace)
    recent = get_store().list_recent(limit=50)
    by_name = {d.vcluster_name: d.to_dict() for d in recent if d.vcluster_name}
    return {
        "host_namespace": settings.vcluster_host_namespace,
        "live": live,
        "tracked": list(by_name.values()),
    }


@app.get("/api/clusters")
async def list_clusters(_user: User = Depends(get_current_user)):
    """History for Active + Failed tabs, pandas groupby (repo, branch).

    Response shape::
      {
        "active": [{"key", "label", "count", "deployments": [...]}],
        "failed": [{"key", "label", "count", "deployments": [...]}]
      }
    """
    db = get_store()
    # Dev/mock ONLY: advance time-based phases so mock deploys reach ready.
    # In production (GitHub App configured) phase is driven by runner callbacks
    # (/api/runner/events). Never mock-advance real runs — that turned failed
    # deployments into "ready"/success.
    if gh_client is None:
        for d in db.list_recent():
            if d.run_id is None:
                db.refresh_phase(d)
    return build_history_groups(db.list_history())


@app.get("/api/clusters/{deployment_id}")
async def cluster_status(deployment_id: str, _user: User = Depends(get_current_user)):
    dep = get_store().get(deployment_id)
    if dep is None:
        raise HTTPException(status_code=404, detail="Deployment not found")
    # Mock-advance only in dev (no GitHub App); prod phase comes from runner callbacks.
    if gh_client is None and dep.run_id is None:
        get_store().refresh_phase(dep)
    return dep.to_dict()


@app.get("/api/clusters/{deployment_id}/stream")
async def cluster_stream(deployment_id: str, _user: User = Depends(get_current_user)):
    dep = get_store().get(deployment_id)
    if dep is None:
        raise HTTPException(status_code=404, detail="Deployment not found")
    return StreamingResponse(
        deployment_event_stream(deployment_id, gh_client, get_store()),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


def _sanitize_vcluster_name(repo: str, branch: str) -> str:
    """Mirror workflows/rascaas/sanitize_vcluster_name.py (tmp-<reponame>-<branch>).

    Same string is host namespace + vCluster release (one virtual cluster per namespace).
    """
    import re

    def slug(part: str) -> str:
        s = (part or "").strip().lower().replace("/", "-").replace("_", "-")
        s = re.sub(r"[^a-z0-9-]+", "-", s)
        return re.sub(r"-+", "-", s).strip("-")

    branch_slug = slug(branch) or "branch"
    repo_raw = (repo or "").strip()
    if "/" in repo_raw:
        repo_raw = repo_raw.rsplit("/", 1)[-1]
    repo_slug = slug(repo_raw)
    if repo_slug:
        name = f"tmp-{repo_slug}-{branch_slug}"
    else:
        name = f"tmp-{branch_slug}"
    return name[:63].rstrip("-")


@app.post("/api/deploy")
async def deploy_cluster(body: DeployRequest, _user: User = Depends(get_current_user)):
    dispatch_repo = (settings.github_dispatch_repo or "").strip() or body.repo
    dispatch_ref = (settings.github_dispatch_ref or "").strip() or "main"
    workflow = await _resolve_workflow(dispatch_repo)
    # TTL dropdown: only 3d / 5d / 7d
    ttl = (body.ttl or "").strip().lower()
    if ttl and ttl not in ("3d", "5d", "7d"):
        raise HTTPException(
            status_code=422,
            detail="TTL must be one of: 3d, 5d, 7d",
        )
    if not ttl:
        ttl = "3d"
    body = body.model_copy(update={"ttl": ttl})
    vcluster_name = _sanitize_vcluster_name(body.repo, body.branch)
    db = get_store()
    trace_id = trace_id_ctx.get()
    if not trace_id or trace_id == "-":
        from app.tracing import new_trace_id

        trace_id = new_trace_id()

    with span(
        "deploy.request",
        repo=body.repo,
        branch=body.branch,
        user=_user.email or _user.sub,
    ):
        log.info(
            "deploy request user=%s repo=%s branch=%s vcluster=%s force=%s",
            _user.email or _user.sub,
            body.repo,
            body.branch,
            vcluster_name,
            body.force,
            extra={
                "event": "deploy_request",
                "repo": body.repo,
                "branch": body.branch,
                "user": _user.email or _user.sub,
                "trace_id": trace_id,
            },
        )

        # Two-phase Redis: inflight (short) at start; live (8d) only after ready.
        # Concurrent deploys blocked by either key. Fail → release inflight only.
        locks = get_lock_store()
        dep_id = uuid4().hex[:12]

        if body.force:
            acq = await locks.force_acquire_inflight(vcluster_name, dep_id)
        else:
            # Host cluster is source of truth for "env still exists".
            # kubectl delete leaves SQLite ready + Redis live; reconcile those orphans.
            on_host = vcluster_exists(vcluster_name, settings.vcluster_host_namespace)

            live = db.find_visible_by_vcluster(vcluster_name)
            if live is not None:
                if on_host:
                    log.warning(
                        "deploy blocked — successful deploy still recorded id=%s vcluster=%s",
                        live.id,
                        vcluster_name,
                        extra={
                            "event": "deploy_conflict_ready",
                            "holder": live.id,
                            "repo": body.repo,
                            "branch": body.branch,
                            "trace_id": trace_id,
                        },
                    )
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            f"Successful deployment still active for {vcluster_name} "
                            f"(id={live.id}). Pass force=true to replace it, or tear down first."
                        ),
                    )
                # Ready in DB, gone on host (manual kubectl delete, etc.).
                db.mark_deleted(
                    live,
                    f"Orphan reconcile — {vcluster_name} not on host; cleared for redeploy",
                )
                await locks.release(vcluster_name, live.id)
                log.warning(
                    "orphan ready reconciled id=%s vcluster=%s — lock released",
                    live.id,
                    vcluster_name,
                    extra={
                        "event": "orphan_ready_reconciled",
                        "holder": live.id,
                        "vcluster": vcluster_name,
                        "trace_id": trace_id,
                    },
                )

            # SQLite: another attempt still provisioning/syncing.
            active = db.find_active_by_vcluster(vcluster_name)
            if active is not None:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        f"Deployment already in progress for {vcluster_name} "
                        f"(id={active.id}, phase={active.phase.value}). Pass force=true to override."
                    ),
                )

            if on_host:
                log.warning(
                    "deploy blocked — live vCluster exists name=%s",
                    vcluster_name,
                    extra={
                        "event": "deploy_conflict",
                        "repo": body.repo,
                        "branch": body.branch,
                        "trace_id": trace_id,
                    },
                )
                raise HTTPException(
                    status_code=409,
                    detail=(
                        f"vCluster {vcluster_name} already exists on the host. "
                        "Pass force=true to reconnect/redeploy, or delete the vCluster first."
                    ),
                )

            # Heal legacy: live key held by a non-ready row (old acquire-at-start).
            live_holder = await locks.get_live_holder(vcluster_name)
            if live_holder:
                holder_dep = db.get(live_holder)
                holder_phase = None
                if holder_dep is not None:
                    holder_phase = (
                        holder_dep.phase
                        if isinstance(holder_dep.phase, ClusterPhase)
                        else ClusterPhase(holder_dep.phase)
                    )
                if holder_dep is None or holder_phase != ClusterPhase.READY:
                    await locks.heal_stale_live_key(vcluster_name)
                    log.warning(
                        "healed stale live key vcluster=%s holder=%s phase=%s",
                        vcluster_name,
                        live_holder,
                        holder_phase.value if holder_phase else "missing",
                        extra={
                            "event": "lock_live_healed_pre_acquire",
                            "holder": live_holder,
                            "token": dep_id,
                            "trace_id": trace_id,
                        },
                    )

            acq = await locks.try_acquire_inflight(vcluster_name, dep_id)
            # Stale Redis (host empty, no SQLite in-flight):
            #   live denied + non-ready holder → heal live, retry inflight
            #   inflight denied + missing/failed/ready holder → steal inflight only
            # Never steal a real in-progress inflight (provisioning/syncing).
            if not acq.acquired and acq.holder:
                holder_dep = db.get(acq.holder)
                holder_phase = None
                if holder_dep is not None:
                    holder_phase = (
                        holder_dep.phase
                        if isinstance(holder_dep.phase, ClusterPhase)
                        else ClusterPhase(holder_dep.phase)
                    )
                stale = (
                    holder_dep is None
                    or holder_phase == ClusterPhase.FAILED
                    or holder_phase == ClusterPhase.READY
                )
                if stale and acq.kind == "live":
                    log.warning(
                        "stale live key cleared key=%s holder=%s → retry inflight as %s",
                        acq.key,
                        acq.holder,
                        dep_id,
                        extra={
                            "event": "lock_stale_live_cleared",
                            "holder": acq.holder,
                            "token": dep_id,
                            "trace_id": trace_id,
                        },
                    )
                    await locks.heal_stale_live_key(vcluster_name)
                    acq = await locks.try_acquire_inflight(vcluster_name, dep_id)
                    if not acq.acquired and acq.kind == "inflight" and acq.holder:
                        holder_dep = db.get(acq.holder)
                        holder_phase = None
                        if holder_dep is not None:
                            holder_phase = (
                                holder_dep.phase
                                if isinstance(holder_dep.phase, ClusterPhase)
                                else ClusterPhase(holder_dep.phase)
                            )
                        stale = (
                            holder_dep is None
                            or holder_phase == ClusterPhase.FAILED
                            or holder_phase == ClusterPhase.READY
                        )
                if not acq.acquired and stale and acq.kind == "inflight":
                    log.warning(
                        "stale inflight stolen key=%s holder=%s → %s phase=%s",
                        acq.key,
                        acq.holder,
                        dep_id,
                        holder_phase.value if holder_phase else "missing",
                        extra={
                            "event": "lock_stale_inflight_stolen",
                            "holder": acq.holder,
                            "token": dep_id,
                            "trace_id": trace_id,
                        },
                    )
                    acq = await locks.steal_inflight(vcluster_name, dep_id)

        if not acq.acquired:
            log.warning(
                "deploy blocked — redis lock held key=%s holder=%s kind=%s",
                acq.key,
                acq.holder,
                acq.kind,
                extra={
                    "event": "deploy_lock_conflict",
                    "repo": body.repo,
                    "branch": body.branch,
                    "holder": acq.holder,
                    "trace_id": trace_id,
                },
            )
            raise HTTPException(
                status_code=409,
                detail=(
                    f"Environment busy or already deployed (lock on {vcluster_name}; "
                    f"holder={acq.holder}, kind={acq.kind or 'unknown'}). "
                    "Pass force=true to override, or wait until failure release / teardown / TTL."
                ),
            )

        superseded = db.supersede_prior_for_vcluster(
            vcluster_name,
            keep_id=dep_id,
            reason=f"Superseded by deploy {dep_id}",
        )
        if superseded:
            log.info(
                "superseded %s prior attempt(s) for vcluster=%s keep=%s",
                superseded,
                vcluster_name,
                dep_id,
                extra={"event": "deploy_supersede", "vcluster": vcluster_name, "count": superseded},
            )

        dep = db.create(
            id=dep_id,
            repo=body.repo,
            branch=body.branch,
            workflow=workflow,
            ttl=body.ttl,
            reason=body.reason,
            linear_ticket=body.linear_ticket,
            dispatch_repo=dispatch_repo,
            dispatch_ref=dispatch_ref,
            vcluster_name=vcluster_name,
            trace_id=trace_id,
        )

        with deployment_context(dep.id, trace_id):
            trigger_ok = True
            if gh_client is not None:
                try:
                    if not (settings.github_dispatch_repo or "").strip():
                        db.append_event(
                            dep,
                            "GITHUB_DISPATCH_REPO unset — dispatching on selected repo (set YOUR_ORG/platform)",
                            level="error",
                            source="system",
                        )
                    # workflow_dispatch inputs are hard-capped at 10 by GitHub. Only send
                    # what differs from the workflow defaults so callback url+token always fit.
                    # Workflow defaults: helm_charts_repo=YOUR_ORG/helm-charts,
                    # helm_charts_branch=main.
                    default_helm_repo = "YOUR_ORG/helm-charts"
                    default_helm_branch = "main"
                    helm_charts_branch = (
                        (body.helm_charts_branch or "").strip() or default_helm_branch
                    )
                    helm_charts_repo = (body.helm_charts_repo or "").strip() or default_helm_repo
                    workflow_inputs = {
                        "variance_repo": body.repo,
                        "branch": body.branch,
                        "ttl": body.ttl,
                        "reason": body.reason,
                        "linear_ticket": body.linear_ticket,
                        "vcluster_name": vcluster_name,
                        "rascaas_deployment_id": dep.id,
                        "rascaas_trace_id": trace_id,
                    }
                    # Only include helm-charts overrides when non-default (saves 2 input slots).
                    if helm_charts_repo != default_helm_repo:
                        workflow_inputs["helm_charts_repo"] = helm_charts_repo
                    if helm_charts_branch != default_helm_branch:
                        workflow_inputs["helm_charts_branch"] = helm_charts_branch
                    token = (settings.runner_callback_token or "").strip()
                    if token:
                        base = settings.app_base_url.rstrip("/")
                        workflow_inputs["rascaas_callback_url"] = f"{base}/api/runner/events"
                        workflow_inputs["rascaas_callback_token"] = token
                    else:
                        log.warning(
                            "RUNNER_CALLBACK_TOKEN unset — workflow will not POST progress to RaSCaaS",
                            extra={"event": "runner_callback_unconfigured", "deployment_id": dep.id},
                        )
                    # Hard guard: GitHub rejects >10 workflow_dispatch inputs with 422.
                    if len(workflow_inputs) > 10:
                        log.warning(
                            "workflow_dispatch inputs=%d exceed GitHub max 10; trimming",
                            len(workflow_inputs),
                            extra={"event": "dispatch_inputs_over_limit", "deployment_id": dep.id},
                        )
                        for optional_key in ("linear_ticket", "reason", "ttl"):
                            if len(workflow_inputs) <= 10:
                                break
                            if not (workflow_inputs.get(optional_key) or "").strip():
                                workflow_inputs.pop(optional_key, None)
                    with span("github.dispatch", deployment_id=dep.id, repo=dispatch_repo):
                        await gh_client.trigger_workflow(
                            dispatch_repo,
                            dispatch_ref,
                            workflow,
                            inputs=workflow_inputs,
                        )
                    # Provisional Actions link immediately (run id arrives via notify).
                    wf_file = workflow if str(workflow).endswith(".yml") else f"{workflow}.yml"
                    dep.run_url = (
                        f"https://github.com/{dispatch_repo}/actions/workflows/{wf_file}"
                    )
                    db.update(dep)
                    # Resolve the concrete run URL once (dispatch is on platform ref, not variance branch).
                    try:
                        from datetime import timedelta, timezone

                        created = dep.created_at
                        if created.tzinfo is None:
                            created = created.replace(tzinfo=timezone.utc)
                        run = await gh_client.find_workflow_run(
                            dispatch_repo,
                            dispatch_ref,
                            workflow,
                            created - timedelta(seconds=60),
                            attempts=12,
                            interval_s=1.5,
                        )
                        if run:
                            dep.run_id = run.get("id")
                            dep.run_url = run.get("html_url") or dep.run_url
                            db.update(dep)
                            db.append_event(
                                dep,
                                f"GitHub Actions run #{dep.run_id} — {dep.run_url}",
                                source="github",
                            )
                    except Exception:
                        log.exception(
                            "could not resolve workflow run url deployment_id=%s",
                            dep.id,
                        )
                    db.append_event(
                        dep,
                        f"Dispatched {workflow} on {dispatch_repo}@{dispatch_ref} "
                        f"(variance={body.repo} @ {body.branch}, vcluster={vcluster_name}, "
                        f"helm-charts={helm_charts_repo}@{helm_charts_branch}, trace={trace_id})",
                        source="github",
                    )
                    log.info(
                        "dispatched workflow=%s deployment_id=%s → %s@%s run_url=%s",
                        workflow,
                        dep.id,
                        dispatch_repo,
                        dispatch_ref,
                        dep.run_url,
                        extra={
                            "event": "deploy_dispatched",
                            "deployment_id": dep.id,
                            "repo": body.repo,
                            "branch": body.branch,
                            "trace_id": trace_id,
                            "run_url": dep.run_url,
                        },
                    )
                except Exception as exc:
                    trigger_ok = False
                    dep.phase = ClusterPhase.FAILED
                    dep.message = "GitHub Actions dispatch failed"
                    error_detail = str(exc)
                    db.append_event(dep, f"Dispatch failed: {error_detail}", level="error", source="github")
                    db.update(dep)
                    await locks.release_inflight(vcluster_name, dep.id)
                    log.exception(
                        "GitHub dispatch failed deployment_id=%s error=%s",
                        dep.id,
                        error_detail,
                        extra={
                            "event": "deploy_dispatch_failed",
                            "deployment_id": dep.id,
                            "repo": body.repo,
                            "branch": body.branch,
                            "trace_id": trace_id,
                            "error": error_detail,
                        },
                    )
            else:
                db.append_event(dep, "Development mode — mock event stream enabled", source="system")

            return {
                "deployment_id": dep.id,
                "trace_id": trace_id,
                "workflow": workflow,
                "triggered": trigger_ok,
                "stream_url": f"/api/clusters/{dep.id}/stream",
                **dep.to_dict(),
            }
