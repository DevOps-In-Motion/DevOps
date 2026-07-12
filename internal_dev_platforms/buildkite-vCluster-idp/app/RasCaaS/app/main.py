from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

from app.auth import User, get_current_user
from app.config import settings
from app.deployments import ClusterPhase, store
from app.github import GitHubClient, github_api_error_message
from app.sse import deployment_event_stream

APP_DIR = Path(__file__).resolve().parent
TEMPLATE_DIR = APP_DIR / "templates"
STATIC_DIR = APP_DIR / "static"
templates = Jinja2Templates(directory=str(TEMPLATE_DIR))

gh_client: GitHubClient | None = None


def _github_configured() -> bool:
    return bool(
        settings.github_app_id
        and settings.github_app_id != "0"
        and settings.github_installation_id
        and settings.github_installation_id != "0"
        and settings.github_private_key
    )


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
    global gh_client
    if _github_configured():
        jwt_iss = settings.github_client_id or settings.github_app_id
        gh_client = GitHubClient(
            jwt_iss,
            settings.github_installation_id,
            settings.github_private_key,
        )
        await gh_client.init()
    yield
    if gh_client:
        await gh_client.close()


app = FastAPI(lifespan=lifespan)

if STATIC_DIR.is_dir():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


class DeployRequest(BaseModel):
    repo: str
    branch: str
    ttl: str = ""
    reason: str = ""
    linear_ticket: str = ""


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/ready")
async def ready():
    return {"status": "ready"}


@app.get("/")
async def index(request: Request):
    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "app_version": settings.app_version,
            "helm_chart_version": settings.helm_chart_version,
        },
    )


@app.get("/api/repos")
async def list_repos(_user: User = Depends(get_current_user)):
    if gh_client is None:
        return [{"full_name": "kovr/example", "name": "example"}]
    try:
        return await gh_client.list_repos()
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=github_api_error_message(exc),
        ) from exc


@app.get("/api/branches")
async def list_branches(repo: str, _user: User = Depends(get_current_user)):
    if gh_client is None:
        return ["main"]
    try:
        return await gh_client.list_branches(repo)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=github_api_error_message(exc),
        ) from exc


@app.get("/api/version")
async def version_info(_user: User = Depends(get_current_user)):
    return {
        "app_version": settings.app_version,
        "helm_chart_version": settings.helm_chart_version,
    }


@app.get("/api/clusters")
async def list_clusters(_user: User = Depends(get_current_user)):
    deployments = store.list_recent()
    out = []
    for d in deployments:
        if d.run_id is None:
            store.refresh_phase(d)
        out.append(d.to_dict())
    return out


@app.get("/api/clusters/{deployment_id}")
async def cluster_status(deployment_id: str, _user: User = Depends(get_current_user)):
    dep = store.get(deployment_id)
    if dep is None:
        raise HTTPException(status_code=404, detail="Deployment not found")
    if dep.run_id is None:
        store.refresh_phase(dep)
    return dep.to_dict()


@app.get("/api/clusters/{deployment_id}/stream")
async def cluster_stream(deployment_id: str, _user: User = Depends(get_current_user)):
    dep = store.get(deployment_id)
    if dep is None:
        raise HTTPException(status_code=404, detail="Deployment not found")
    return StreamingResponse(
        deployment_event_stream(deployment_id, gh_client),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/api/deploy")
async def deploy_cluster(body: DeployRequest, _user: User = Depends(get_current_user)):
    workflow = await _resolve_workflow(body.repo)
    dep = store.create(
        repo=body.repo,
        branch=body.branch,
        workflow=workflow,
        ttl=body.ttl,
        reason=body.reason,
        linear_ticket=body.linear_ticket,
    )

    trigger_ok = True
    if gh_client is not None:
        try:
            dispatch_repo = (settings.github_dispatch_repo or "").strip() or body.repo
            if not (settings.github_dispatch_repo or "").strip():
                store.append_event(
                    dep,
                    "GITHUB_DISPATCH_REPO unset — dispatching on selected repo (set kovr-ai/platform)",
                    level="error",
                    source="system",
                )
            workflow_inputs = {
                "variance_repo": body.repo,
                "branch": body.branch,
                "ttl": body.ttl,
                "reason": body.reason,
                "linear_ticket": body.linear_ticket,
            }
            await gh_client.trigger_workflow(
                dispatch_repo,
                body.branch,
                workflow,
                inputs=workflow_inputs,
            )
            store.append_event(
                dep,
                f"Dispatched {workflow} on {dispatch_repo} (variance={body.repo} @ {body.branch})",
                source="github",
            )
        except Exception as exc:
            trigger_ok = False
            dep.phase = ClusterPhase.FAILED
            dep.message = "GitHub Actions dispatch failed"
            store.append_event(dep, f"Dispatch failed: {exc}", level="error", source="github")
    else:
        store.append_event(dep, "Development mode — mock event stream enabled", source="system")

    store.update(dep)
    return {
        "deployment_id": dep.id,
        "workflow": workflow,
        "triggered": trigger_ok,
        "stream_url": f"/api/clusters/{dep.id}/stream",
        **dep.to_dict(),
    }


