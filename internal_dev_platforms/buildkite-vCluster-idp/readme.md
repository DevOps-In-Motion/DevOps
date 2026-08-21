# RaSCaaS — Rapid Encapsulated Cluster as a Service

On-demand **vCluster** environments for QA / UAT. Engineers pick a service repo and branch in a small IDP UI; GitHub Actions builds the variance image, stands up an ephemeral cluster, and deploys the full application stack with a TTL.

This folder is the DevOps home for that stack: the FastAPI IDP, Helm chart, IAM/CSI prerequisites, and the UAT pipelines.

---

## What it does

```text
Developer  →  RaSCaaS UI (oauth2-proxy + FastAPI)
                 │  workflow_dispatch
                 ▼
           uat-deploy.yml
                 │
                 ├─ build variance image → ECR (uat-temp)
                 ├─ create vCluster  tmp-<repo>-<branch>
                 ├─ Helm full stack (:latest for everything else)
                 └─ DNS  {vcluster}.uat.example.com → shared QA ALB
```

| Piece | Role |
|-------|------|
| **IDP UI** | Repo / branch / TTL / ticket form; live progress via SSE; Active / Failed tabs |
| **oauth2-proxy + OIDC** | Browser auth (Cognito on QA; Keycloak locally) |
| **`uat-deploy.yml`** | Only UAT entrypoint — build, vCluster, Helm, Route53, callbacks |
| **`rascaas-build.yml`** | Build/push IDP image + UAT ECR cleanup CronJob image |
| **TTL cleanup Job** | Tears down the vCluster when the lease expires |
| **ECR cleanup CronJob** | Deletes aged tags from the temp ECR repo (not the IDP itself) |

Teardown is **event-driven**: the cleanup path (or an operator) POSTs `/api/runner/deleted`; RaSCaaS does not poll the cluster for lifecycle.

---

## Layout

```text
buildkite-vCluster-idp/
├── README.md                 ← you are here
├── app/RasCaaS/              ← IDP app, Helm chart, IAM, ecr-cleanup
│   ├── app/                  # FastAPI + Jinja UI
│   ├── helm/rascaas/         # Chart (Keycloak optional, oauth2-proxy, FastAPI)
│   ├── helm/_crds/           # Namespace, gateway, SAs, secrets / CSI SPCs
│   ├── helm/_values/         # Env overlays (e.g. QA)
│   ├── iam/                  # IRSA / GHA push policies
│   ├── ecr-cleanup/          # Standalone cleanup image
│   └── docker-compose.yml    # Local Keycloak + oauth2-proxy + app
├── workflows/rascaas/        # Pipeline helpers (overlay, notify, DNS, …) — used by GHA
├── .github/workflows/        # rascaas-build.yml, uat-deploy.yml
└── infra/                    # Older Buildkite agent Terraform/Ansible (legacy)
```

Deep dive: [`app/RasCaaS/README.md`](app/RasCaaS/README.md) · pipelines: [`workflows/rascaas/README.md`](workflows/rascaas/README.md)

---

## Prerequisites

| Need | Notes |
|------|--------|
| **kubectl** + kubeconfig to the target EKS cluster | QA example: `YOUR_QA_CONTEXT` |
| **Helm 3** | `helm dependency update` pulls Keycloak chart |
| **Docker / Compose** | Local stack only |
| **GitHub App** | Org install with repo + Actions dispatch rights (not a PAT) |
| **Gateway API + AWS LBC gateway CRDs** | Once per cluster — see [`app/RasCaaS/helm/_crds/README.md`](app/RasCaaS/helm/_crds/README.md) |
| **OIDC IdP** | Cognito (QA) or Keycloak (local / alternate) |

---

## Quick start — local (Docker Compose)

Best path to try the UI without EKS.

```bash
cd app/RasCaaS
cp .env.example .env
# Optional: fill GITHUB_* for real repos; leave empty for mock data
docker compose up --build
```

| URL | Purpose |
|-----|---------|
| http://localhost:4180 | **App** (always use this — oauth2-proxy front door) |
| http://localhost:8080 | Keycloak admin (`admin` / `admin`) |

**Test user:** `dev` / `dev` (realm `rascaas`).

Generate a cookie secret if Compose complains:

```bash
python3 -c "import secrets,base64; print(base64.urlsafe_b64encode(secrets.token_bytes(24)).decode().rstrip('='))"
```

---

## Install on EKS (QA)

Commands assume you are in `app/RasCaaS` with `kubectl` pointed at the right cluster.

### 1. Context

```bash
kubectl config get-contexts
kubectl config use-context <your-eks-context>
kubectl cluster-info
```

### 2. Gateway API CRDs (once per cluster)

```bash
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.2.2/config/crd/gateway/gateway-crds.yaml"
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.2.2/config/crd/gateway/gatewayclass.yaml"
kubectl get gatewayclass alb
```

If LBC was already running, restart it after CRDs land:

```bash
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
```

### 3. Namespace, service accounts, secrets

```bash
cd app/RasCaaS

kubectl apply -f helm/_crds/namespace.yaml
kubectl apply -f helm/_crds/vcluster/namespace.yaml
kubectl apply -f helm/_crds/service-accounts/
```

**Secrets — pick one mode:**

| Mode | When | Steps |
|------|------|--------|
| `csi-driver` | QA / prod (AWS Secrets Manager) | Apply `helm/_crds/csi-driver/` SPCs; IRSA role must exist (`iam/`) |
| `plain` | Dev / no CSI | `python3 scripts/render-plain-secrets.py` then `kubectl apply -f helm/_crds/secrets/plain-secrets.yaml` |

QA values default to **CSI** — do not also apply `plain-secrets.yaml` in that mode.

### 4. ALB Gateway + DNS

```bash
kubectl apply -f helm/_crds/gateway/rascaas-gateway-base.yaml
# Set the IAM server-certificate ARN in rascaas-gateway-https.qa.yaml, then:
kubectl apply -f helm/_crds/gateway/rascaas-gateway-https.qa.yaml
kubectl get gateway rascaas-gateway -n rascaas
```

Point DNS (`rascaas.qa.example.com` for QA) at the Gateway ALB address. After Helm is up, confirm ALB listener rules include `/api/runner*` (callbacks bypass oauth2-proxy) — see [`helm/_crds/gateway/README.md`](app/RasCaaS/helm/_crds/gateway/README.md).

### 5. Helm install

```bash
helm dependency update ./helm/rascaas
helm upgrade --install rascaas ./helm/rascaas -n rascaas \
  -f helm/_values/qa-install-values.yaml
```

OIDC (issuer, client ID, callback) must match Cognito (or your IdP). Client secret lives in Secrets Manager / `plain-secrets`, not in the values file. Details: [`app/RasCaaS/README.md`](app/RasCaaS/README.md) § OIDC / oauth2-proxy.

### 6. Verify

```bash
kubectl get pods,svc,httproute -n rascaas
kubectl get gateway rascaas-gateway -n rascaas
```

Open the public URL → Cognito login → IDP home. Deploy should create a `workflow_dispatch` run of `uat-deploy.yml` on the configured GitHub repo.

---

## Pipelines

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| [`.github/workflows/uat-deploy.yml`](.github/workflows/uat-deploy.yml) | `workflow_dispatch` only | Build variance → temp ECR → vCluster → Helm stack → DNS / notify |
| [`.github/workflows/rascaas-build.yml`](.github/workflows/rascaas-build.yml) | `workflow_dispatch` only | Build/push IDP + `rascaas-uat-ecr-cleanup` images |

Helpers live under [`workflows/rascaas/`](workflows/rascaas/) (`stack-services.yaml`, overlay renderer, Route53, notify, TTL cleanup Job).

Configure the IDP with:

```env
GITHUB_DISPATCH_REPO=<org>/<repo-that-hosts-uat-deploy>
GITHUB_DISPATCH_REF=main
DEFAULT_WORKFLOW=uat-deploy.yml
```

UAT automation is **platform-only** — service repos do not host matching deploy workflows.

---

## Build the IDP image

```bash
# linux/amd64 for EKS nodes
docker build --platform linux/amd64 -t <ecr-registry>/rascaas:<tag> ./app/RasCaaS
```

Or run `rascaas-build.yml` via Actions. Push only when you intend to publish (and have registry auth).

Cleanup image: build from `app/RasCaaS/ecr-cleanup/` (see that folder’s README).

---

## Related docs

| Doc | Content |
|-----|---------|
| [`app/RasCaaS/README.md`](app/RasCaaS/README.md) | GitHub App setup, secrets modes, Cognito, troubleshooting |
| [`app/RasCaaS/helm/_crds/README.md`](app/RasCaaS/helm/_crds/README.md) | Cluster prerequisites checklist |
| [`app/RasCaaS/helm/_values/README.md`](app/RasCaaS/helm/_values/README.md) | Env overlays |
| [`app/RasCaaS/iam/README.md`](app/RasCaaS/iam/README.md) | IRSA / LBC / GHA roles |
| [`workflows/rascaas/README.md`](workflows/rascaas/README.md) | UAT pipeline design |
| [`.github/workflows/README.md`](.github/workflows/README.md) | Workflow index |

---

## Legacy: Buildkite agents

[`infra/`](infra/) and [`buildkite.sh`](buildkite.sh) are an older Buildkite agent Terraform/Ansible layout. They are **not** required for RaSCaaS (GitHub Actions drives UAT). Keep them only if you still operate Buildkite agents from this tree.
