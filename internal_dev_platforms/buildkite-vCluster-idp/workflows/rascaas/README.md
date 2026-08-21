# RaSCaaS UAT workflows (platform-only)

## Repository naming

| Context | Name |
|---------|------|
| Local clone / paths in this monorepo | **`platform-testing`** |
| GitHub (Actions, `GITHUB_DISPATCH_REPO`, `gh`) | **`platform`** → `kovr-ai/platform` |

All UAT automation runs on the **GitHub `platform` repo**. Service repos (bff, ds, ai-workers, …) do **not** host UAT build/deploy workflows.

## Pipelines

| Workflow | Purpose |
|----------|---------|
| [`.github/workflows/uat-deploy.yml`](../../.github/workflows/uat-deploy.yml) | **Only** UAT entrypoint (`workflow_dispatch` from RaSCaaS) — never on push |
| [`.github/workflows/rascaas-build.yml`](../../.github/workflows/rascaas-build.yml) | Build/push IDP + `rascaas-uat-ecr-cleanup` (`workflow_dispatch` only — never on push) |

## Variance catalog (`stack-services.yaml`)

| GitHub repo (`kovr-ai/…`) | Helm key | Notes |
|---------------------------|----------|--------|
| `bff-service-backend` | `bff-backend` | Needs `NPM_TOKEN` |
| `ds` | `ds-service` | |
| `ai-workers` | `ai-workers` | |
| `llm-gateway` | `llm-gateway` | |
| `frontend-app` | `frontend-app` | |
| `kovr-resource-collector` | `kovr-resource-collector` | Default branch **`prod-deploy`** (not `main`) |

Not buildable: `ai-app-server` (no `kovr-ai/ai-app-server` repo), `askai`, `platform`, `RasCaaS`, `helm-charts`.

All service repos are **private**. `uat-deploy` checkouts use **`IMPORT_APP_ID` / `IMPORT_APP_PRIVATE_KEY`** (GitHub App token) — plain `GITHUB_TOKEN` returns “Repository not found” for cross-repo private clones.

## Why platform-only

- **Single blast radius** — one workflow, one set of AWS/IRSA secrets, one audit trail
- **RaSCaaS** always dispatches `uat-deploy.yml` on platform with `variance_repo` = the repo/branch chosen in the UI
- Dispatch **ref** is the platform branch that owns the workflow (`GITHUB_DISPATCH_REF`, default `main`) — not the variance branch
- The workflow **checks out** the variance service repo, builds one image into the **temp ECR repo**, creates/connects `tmp-<sanitized-branch>`, then deploys the full stack via Helm (`:latest` for everything else)

## Layout

| Path | Purpose |
|------|---------|
| `.github/workflows/uat-deploy.yml` | UAT workflow entrypoint |
| `.github/workflows/rascaas-build.yml` | RaSCaaS IDP + UAT ECR cleanup images |
| `RasCaaS/ecr-cleanup/` | Standalone cleanup image (not the IDP) |
| `workflows/rascaas/stack-services.yaml` | Repo name → Helm key / ECR image |
| `workflows/rascaas/render_uat_overlay.py` | Helm overlay (variance temp image + others `:latest`) |
| `workflows/rascaas/sanitize_vcluster_name.py` | → `tmp-<reponame>-<branch>` (ns + release) |
| `workflows/rascaas/uat_route53.py` | Ephemeral DNS upsert/delete: `{vcluster}.uat.kovrai.com` → shared QA ALB |
| `workflows/rascaas/parse_ttl.py` | `72h` → seconds |
| `workflows/rascaas/render_vcluster_cleanup_job.py` | Host TTL cleanup Job (DNS + vCluster delete) |
| `workflows/rascaas/rascaas_notify.py` | POST progress to RaSCaaS `/api/runner/events` |
| **`kovr-ai/helm-charts`** (checked out @ branch) | Umbrella chart `kovr/` + baseline `values.yaml` |

## RaSCaaS env

```env
GITHUB_DISPATCH_REPO=kovr-ai/platform
GITHUB_DISPATCH_REF=main
DEFAULT_WORKFLOW=uat-deploy.yml
```

Dispatch inputs: `variance_repo`, `branch`, `ttl`, `reason`, `linear_ticket`, `vcluster_name` (optional), `helm_charts_repo` (default `kovr-ai/helm-charts`), `helm_charts_branch` (default **`create-kovr-parent-chart`** — not the variance branch), plus optional RaSCaaS callback fields below.

### RaSCaaS progress callback

RaSCaaS passes these on `workflow_dispatch` when `RUNNER_CALLBACK_TOKEN` is configured:

| Input | Purpose |
|-------|---------|
| `rascaas_deployment_id` | SQLite deployment id in the IDP |
| `rascaas_callback_url` | `{APP_BASE_URL}/api/runner/events` |
| `rascaas_callback_token` | Bearer token (same as FastAPI `RUNNER_CALLBACK_TOKEN`) |
| `rascaas_trace_id` | Deploy-scoped trace id (correlates browser → FastAPI → GHA → runner POSTs) |

Workflow helper: [`rascaas_notify.py`](rascaas_notify.py) — milestone POSTs (resolve / build / vcluster / helm / failure). No-ops if inputs empty (manual dispatches). Gateway routes `/api/runner` straight to FastAPI (bypasses oauth2-proxy).

**Branch lock signal:** after `helm upgrade --wait` succeeds, the step
`Notify RaSCaaS — deployment created (branch lock)` POSTs `--phase ready`.
RaSCaaS creates the Redis lock (`rascaas:lock:<vcluster>`, 8-day TTL) **only**
on that event — not at dispatch time. Failures never create a lock.

```bash
# Example (token must match cluster secret)
python3 workflows/rascaas/rascaas_notify.py \
  --phase syncing \
  --line "Build: starting"
```

### Deploy job flow

1. Resolve catalog + sanitize vCluster name (`tmp-<branch>`) + resolve **helm-charts branch** (`create-kovr-parent-chart`)
2. Checkout **only the variance service repo** @ selected branch → build & push to **`${ECR}/kovr-uat-temp:ras-<image>-<branch>-<sha>`** (temp repo; not permanent service repos)
3. Checkout **`kovr-ai/helm-charts` @ `create-kovr-parent-chart`** → `helm dependency update`
4. Create/connect vCluster on the host
5. Helm install: overlay sets **variance = temp image URI**, **all other stack services = `:latest`**
6. Optional TTL Job → `vcluster delete`
7. Host CronJob (`rascaas-uat-ecr-cleanup` image) deletes digests in `kovr-uat-temp` older than **14 calendar days**

### API / SDK notes (verified)

| API | Use |
|-----|-----|
| GitHub `POST …/actions/workflows/{id}/dispatches` | `ref` = platform branch (`main`); `inputs` = variance + `vcluster_name`. GitHub App installation token. |
| `loft-sh/setup-vcluster` | Installs CLI on `ubuntu-latest` (no special runner image). |
| `vcluster create/connect --print` | Supported; remote CI needs port-forward or exposed API ([vCluster access docs](https://www.vcluster.com/docs/vcluster/manage/accessing-vcluster)). |
| Kubernetes in-cluster API | RaSCaaS lists live `tmp-*` via ClusterRole (dedicated ns per env + legacy `vcluster` ns). |

### Best practices applied

- Platform-only workflow (no per-service UAT pipelines)
- Deterministic identity: **`tmp-<reponame>-<branch>`** = host namespace **and** vCluster Helm release (**one** virtual cluster per namespace). Never pack multiple UAT envs into a shared `vcluster` ns.
- Ephemeral DNS: `{tmp-…}.uat.kovrai.com` A-alias → shared QA ALB (`uat_route53.py`). Needs ACM `*.uat.kovrai.com` + host HTTPRoute into the vCluster for HTTPS end-to-end. TTL cleanup deletes the record when `UAT_ROUTE53_ROLE_ARN` IRSA is set.
- Concurrency group per vCluster name (no parallel double-deploys)
- SQLite gate + live cluster check before dispatch (`409` unless `force`)
- TTL cleanup Job on host
- Variance images isolated in temp ECR + 14-day CronJob GC (separate image/SA from IDP)
- Least-privilege workflow `permissions`
- Pin vCluster CLI (`v0.22.1`) to match cleanup image

## GitHub configuration (`kovr-ai/platform` only)

| Type | Name | Value / notes |
|------|------|----------------|
| Variable | `ECR_REGISTRY` | `650251729525.dkr.ecr.us-west-2.amazonaws.com` |
| Variable | `AWS_REGION` | `us-west-2` |
| Variable | `EKS_CLUSTER_NAME` | optional; default `qa-kovr-app-cluster` |
| Variable | `ECR_UAT_TEMP_REPO` | optional; default `kovr-uat-temp` |
| Secret | `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::650251729525:role/GithubBackendDeployRole` (ECR push) |
| Secret | `AWS_EKS_DEPLOY_ROLE_ARN` | optional; default `arn:aws:iam::650251729525:role/DevopsCICDRole` (same as QA `deploy-*-eks.yml`) |
| Secret | `IMPORT_APP_ID` / `IMPORT_APP_PRIVATE_KEY` | GitHub App for private checkout of variance + `helm-charts` |
| Secret | `NPM_TOKEN` | Optional fallback for BFF; prefer AWS SM `global/github/npm-token` (same as BFF deploy) |

**AWS Secrets Manager** (read by `GithubBackendDeployRole` during build — not GitHub secrets):

| SM secret | Purpose |
|-----------|---------|
| `global/Chainguard/Credentials` | `username`/`password` → `podman`/`docker login cgr.dev` (private `cgr.dev/kovr.ai/*` bases) |
| `global/github/npm-token` | `{ "token": "…" }` for BFF `npm.pkg.github.com` |

**Cluster auth** matches other QA EKS workflows: OIDC → `DevopsCICDRole` → `aws eks update-kubeconfig`. No kubeconfig secret.

## Do not add per-repo UAT workflows

Do not copy UAT workflows into `bff-service-backend`, `ds`, etc. Manual builds from a service repo Actions tab are intentionally unsupported for UAT.
