import asyncio
import logging
import re
import time
from datetime import datetime, timezone
from typing import Any, Optional

import httpx
import jwt as pyjwt

logger = logging.getLogger(__name__)

GH_API = "https://api.github.com"

_PEM_BLOCK_RE = re.compile(
    r"-----BEGIN ([A-Z0-9 ]+)-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END \1-----",
    re.DOTALL,
)


def normalize_private_key(pem: str) -> str:
    """Accept .env single-line PEM (no newlines) and standard multi-line PEM."""
    if not pem or not pem.strip():
        return pem
    text = pem.strip().strip('"').strip("'").replace("\\n", "\n")
    if "\n" in text and text.count("\n") >= 2:
        return text if text.endswith("\n") else text + "\n"
    match = _PEM_BLOCK_RE.search(text.replace("\n", ""))
    if not match:
        return text
    label, body = match.group(1), re.sub(r"\s+", "", match.group(2))
    wrapped = "\n".join(body[i : i + 64] for i in range(0, len(body), 64))
    return f"-----BEGIN {label}-----\n{wrapped}\n-----END {label}-----\n"


def github_api_error_message(exc: BaseException) -> str:
    if isinstance(exc, httpx.HTTPStatusError):
        try:
            body = exc.response.json()
            msg = body.get("message") or body.get("error")
            if msg:
                return f"GitHub API {exc.response.status_code}: {msg}"
        except Exception:
            pass
        return f"GitHub API {exc.response.status_code}: {exc.response.text[:200]}"
    return str(exc)


def workflow_filename(workflow: str) -> str:
    if workflow.startswith(".github/workflows/"):
        return workflow.rsplit("/", 1)[-1]
    return workflow


def parse_github_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


class GitHubClient:
    def __init__(self, jwt_iss: str, installation_id: str, private_key: str):
        self.jwt_iss = jwt_iss
        self.installation_id = installation_id
        self.private_key = normalize_private_key(private_key)
        self._token: Optional[str] = None
        self._token_expires_at: float = 0
        self._client: Optional[httpx.AsyncClient] = None

    async def init(self):
        self._client = httpx.AsyncClient(
            base_url=GH_API,
            headers={
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            timeout=30.0,
        )

    async def close(self):
        if self._client:
            await self._client.aclose()

    def _generate_app_jwt(self) -> str:
        now = int(time.time())
        payload = {
            "iat": now - 60,
            "exp": now + 540,
            "iss": self.jwt_iss,
        }
        try:
            return pyjwt.encode(payload, self.private_key, algorithm="RS256")
        except Exception as exc:
            raise ValueError(
                "Invalid GITHUB_PRIVATE_KEY — use the .pem from GitHub with proper line breaks"
            ) from exc

    async def _get_installation_token(self) -> str:
        if self._token and time.time() < self._token_expires_at - 60:
            return self._token

        app_jwt = self._generate_app_jwt()
        async with httpx.AsyncClient() as client:
            r = await client.post(
                f"{GH_API}/app/installations/{self.installation_id}/access_tokens",
                headers={
                    "Authorization": f"Bearer {app_jwt}",
                    "Accept": "application/vnd.github+json",
                },
            )
            r.raise_for_status()
            data = r.json()

        self._token = data["token"]
        self._token_expires_at = time.time() + 3600
        return self._token

    async def _headers(self) -> dict:
        token = await self._get_installation_token()
        return {"Authorization": f"Bearer {token}"}

    async def list_repos(self) -> list[dict]:
        headers = await self._headers()
        r = await self._client.get(
            "/installation/repositories",
            headers=headers,
            params={"per_page": 100},
        )
        r.raise_for_status()
        repos = r.json().get("repositories", [])
        return [{"full_name": repo["full_name"], "name": repo["name"]} for repo in repos]

    async def list_branches(self, repo: str) -> list[str]:
        headers = await self._headers()
        r = await self._client.get(
            f"/repos/{repo}/branches",
            headers=headers,
            params={"per_page": 100},
        )
        r.raise_for_status()
        return [b["name"] for b in r.json()]

    async def list_workflows(self, repo: str) -> list[dict]:
        headers = await self._headers()
        r = await self._client.get(
            f"/repos/{repo}/actions/workflows",
            headers=headers,
        )
        r.raise_for_status()
        workflows = r.json().get("workflows", [])
        return [
            {"id": w["id"], "name": w["name"], "path": w["path"]}
            for w in workflows
            if w["state"] == "active"
        ]

    async def trigger_workflow(
        self, repo: str, branch: str, workflow: str, inputs: dict | None = None
    ) -> dict:
        headers = await self._headers()
        wf = workflow_filename(workflow)
        r = await self._client.post(
            f"/repos/{repo}/actions/workflows/{wf}/dispatches",
            headers=headers,
            json={"ref": branch, "inputs": inputs or {}},
        )
        if r.status_code == 204:
            return {"triggered": True, "workflow_file": wf}
        r.raise_for_status()
        return r.json()

    def _run_matches_workflow(self, run: dict, workflow: str) -> bool:
        wf = workflow_filename(workflow)
        path = run.get("path") or ""
        return path.endswith(wf) or path.endswith(f"/{wf}")

    async def find_workflow_run(
        self,
        repo: str,
        branch: str,
        workflow: str,
        created_after: datetime,
        *,
        attempts: int = 30,
        interval_s: float = 2.0,
    ) -> Optional[dict]:
        headers = await self._headers()
        for _ in range(attempts):
            r = await self._client.get(
                f"/repos/{repo}/actions/runs",
                headers=headers,
                params={
                    "branch": branch,
                    "event": "workflow_dispatch",
                    "per_page": 15,
                },
            )
            r.raise_for_status()
            for run in r.json().get("workflow_runs", []):
                if not self._run_matches_workflow(run, workflow):
                    continue
                if parse_github_time(run["created_at"]) >= created_after:
                    return run
            await asyncio.sleep(interval_s)
        return None

    async def get_workflow_run(self, repo: str, run_id: int) -> dict:
        headers = await self._headers()
        r = await self._client.get(
            f"/repos/{repo}/actions/runs/{run_id}",
            headers=headers,
        )
        r.raise_for_status()
        return r.json()

    async def list_workflow_jobs(self, repo: str, run_id: int) -> list[dict]:
        headers = await self._headers()
        r = await self._client.get(
            f"/repos/{repo}/actions/runs/{run_id}/jobs",
            headers=headers,
            params={"per_page": 100},
        )
        r.raise_for_status()
        return r.json().get("jobs", [])

    def run_snapshot(self, run: dict, jobs: list[dict]) -> dict[str, Any]:
        """Normalize GitHub run + jobs for UI and SSE."""
        job_rows = []
        for job in jobs:
            steps = [
                {
                    "name": s.get("name"),
                    "status": s.get("status"),
                    "conclusion": s.get("conclusion"),
                }
                for s in job.get("steps", [])
            ]
            job_rows.append(
                {
                    "id": job.get("id"),
                    "name": job.get("name"),
                    "status": job.get("status"),
                    "conclusion": job.get("conclusion"),
                    "html_url": job.get("html_url"),
                    "steps": steps,
                }
            )
        return {
            "run_id": run.get("id"),
            "run_url": run.get("html_url"),
            "status": run.get("status"),
            "conclusion": run.get("conclusion"),
            "workflow_name": run.get("name"),
            "jobs": job_rows,
        }
