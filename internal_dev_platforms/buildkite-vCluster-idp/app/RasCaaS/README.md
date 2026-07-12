# RaSCaaS

RaSCaaS is a Rapid encapSulated Cluster as a Service. This repo is designed to spin up a vCluster in our QA environment on demand (rapid test cluster). This allows developers to validate against production-like data when needed.


## Toolchain

  - Github Actions (w/ runners)
  - vCluster
  - EKS
  - cert-manager + ACM
  - Podman (image builder on GHA runner)
  - FastAPI w/ Jinja2 (UI web framework)
  - Helm 
  - [OAuth2 Proxy](https://oauth2-proxy.github.io)
  - KeyCloak
  - OIDC - auth
  - CSI Secrets Store
  - mailu


## Frontend

Internal Developer Platform for QA and internal feature testing. This site is a basic Hugo site with github CI as our engine to drive deployment of the vClusters for UAT environments. 

Site with dropdown menu for: 
 - Repo
 - Branch
 - Time To Live
 - Reason For Testing
 - Linear Ticket 


## Cluster Deployment Flow

Form is filled (button pressed) → GitHub Actions **`uat-deploy.yml`** on **`kovr-ai/platform`** → build **variance** image for the selected repo → Helm deploy full stack (baseline images for all other services) → vCluster / QA.

> **Naming:** local monorepo folder = `platform-testing`; GitHub repository = `platform`.

**Platform-only:** all builds and Helm deploys run on the **platform** GitHub repo — not in each service repo (smaller blast radius).

| Path (local `platform-testing/` clone) | Purpose |
|------------------------------|---------|
| `.github/workflows/uat-deploy.yml` | Sole workflow entrypoint |
| `workflows/rascaas/stack-services.yaml` | Repo → Helm key / ECR image map |
| `workflows/rascaas/render_uat_overlay.py` | Helm overlay generator |

See `platform-testing/workflows/rascaas/README.md`.

Set in RaSCaaS `.env` (required for production):

```env
GITHUB_DISPATCH_REPO=kovr-ai/platform
DEFAULT_WORKFLOW=uat-deploy.yml
```

RaSCaaS passes `variance_repo` = UI-selected service; the platform workflow checks out that repo, builds one image, deploys the stack with baseline images for all other services.

GitHub **variables/secrets** live only on **`kovr-ai/platform`**: `ECR_REGISTRY`, `AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`, `VCLUSTER_KUBECONFIG_B64` (deploy into vCluster), `VCLUSTER_HOST_KUBECONFIG_B64` (TTL cleanup Job on host), `NPM_TOKEN`. 

## Auth

Browser traffic goes through **oauth2-proxy** (OIDC). The app validates `X-Forwarded-Access-Token` from Keycloak (or your IdP). See **Local OAuth stack** below.

## Local OAuth stack (Docker Compose)

Full local test environment: **Keycloak** + **oauth2-proxy** + **RaSCaaS** (FastAPI).

```bash
cd platform-testing/RasCaaS
cp .env.example .env
docker compose up --build
```

Wait until Keycloak is healthy (~60–90s on first boot). Then open:

| URL | Purpose |
|-----|---------|
| http://localhost:4180 | **App with OAuth** (use this in the browser) |
| http://localhost:8000 | Not published (FastAPI is internal; use **4180** only) |
| http://localhost:8080 | Keycloak admin (`admin` / `admin`) |

**Test user:** `dev` / `dev` (realm `rascaas`, imported from `docker/keycloak/realm-rascaas.json`)

Use **4180** only. FastAPI is **not** exposed on port 8000 (internal to Docker). The compose stack sets `TRUST_OAUTH2_PROXY_IDENTITY=true` so `/api/*` accepts oauth2-proxy identity headers after you sign in.

**Sign out:** use **Sign out** in the app bar (calls oauth2-proxy `/oauth2/sign_out`, clears the session cookie, returns to sign-in).

**Troubleshooting: “Failed to load repositories”**

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| HTTP 401 on `/api/repos` | Not signed in on **:4180** (or stale session) | Open **http://localhost:4180**, log in (`dev` / `dev`), hard-refresh |
| HTTP **500** on `/api/repos` (proxy works, no repos) | JWT validation tried to fetch JWKS at `localhost:8080` inside the container | `docker compose up --build` — app trusts `X-Auth-Request-*` first and uses `OIDC_JWKS_URL=http://keycloak:8080/.../certs` |
| HTTP 401 + “Invalid token” | OIDC access token not validating | Same as above; sign in again on **:4180** |
| HTTP 502 + GitHub message in toast | GitHub App credentials / permissions | Fix `GITHUB_PRIVATE_KEY`, `GITHUB_INSTALLATION_ID`, repo access on the app install |
| Mock repo `kovr/example` only | `GITHUB_*` incomplete in `.env` | Set app id, installation id, private key; `docker compose up --build` |
| `connection refused` on :8000 | Expected | Use **:4180** — port 8000 is intentionally not published |

**GitHub:** leave `GITHUB_*` empty in `.env` for mock repos, branches, and SSE timelines.

**Secrets (dev only, in `.env.example`):**

- `OAUTH2_PROXY_CLIENT_SECRET=rascaas-local-client-secret`
- `OAUTH2_PROXY_COOKIE_SECRET` — generate a **32-byte** secret (do not use a guessable string):

```bash
python3 -c "import secrets,base64; print(base64.urlsafe_b64encode(secrets.token_bytes(24)).decode().rstrip('='))"
```

Do not use these values outside local Docker.

## Helm secrets (`secrets.mode`)

Deployments always inject sensitive env vars from Kubernetes Secrets (`fastapi-secrets`, `oauth2proxy-secret`). How those secrets are populated is controlled by `helm/rascaas/values.yaml`:

| `secrets.mode` | CSI volume | Secret source |
|----------------|------------|---------------|
| `plain` (default until CSI) | No | `helm/_crds/secrets/plain-secrets.yaml` (copy from `plain-secrets.example.yaml`) |
| `csi-driver` | Yes — mounts `SecretProviderClass` | AWS Secrets Manager via `helm/_crds/secrets/spc.yaml` + IRSA |

```bash
# Testing / no CSI (default)
cp helm/_crds/secrets/plain-secrets.example.yaml helm/_crds/secrets/plain-secrets.yaml
# edit stringData, then:
kubectl apply -f helm/_crds/secrets/plain-secrets.yaml
helm upgrade --install rascaas ./helm/rascaas -n rascaas --set secrets.mode=plain

# Production (AWS SM + CSI)
helm upgrade --install rascaas ./helm/rascaas -n rascaas \
  --set secrets.mode=csi-driver \
  --set secrets.secretProviderClass=rascaas-secrets-provider
```

Apply `helm/_crds/secrets/spc.yaml` only for `csi-driver`. For `plain`, apply `plain-secrets.yaml` before the release (see `helm/_crds/secrets/README.md`).

## AWS Architecture

We use an IAM role to allow access to our production account's RDS and Elasticache from our test cluster's account. For traffic we wire our two VPNs together from private region to private region. 



## Pending Questions 

  - How are we going to give our staff engineers easy onboarded to skip email flow? MailU? Ignore email flow altogether?
  - How do we allow the pull of secrets from another AWS account? 
  - How do we quickly integrate with SES if needed?
  - Create a progress bar? 
  - TLS automation?
  - Simple EC2? Or pod on k8s?
  - Auth into website itself... Google Workspace or KeyCloak + G-Workspace?

---

## Installation reference

Use this section as the install index. RaSCaaS uses a **GitHub App** installed on your organization (not a personal access token). Sensitive values reach the app via Kubernetes Secrets — either synced from AWS Secrets Manager (`secrets.mode=csi-driver`) or pre-created manifests (`secrets.mode=plain`).

### Index

| Step | Topic | Where |
|------|--------|--------|
| 1 | Create and install a GitHub App on the org | [GitHub App (organization)](#github-app-organization) |
| 2 | Configure target repos and workflow | [Workflow requirements](#workflow-requirements) |
| 3 | Store credentials (local `.env` or AWS SM) | [Wire GitHub credentials](#wire-github-credentials) |
| 4 | Cluster prerequisites (Gateway API CRDs, namespace, gateway, IRSA) | [EKS prerequisites](#eks-prerequisites) · [`helm/_crds/README.md`](helm/_crds/README.md) |
| 5 | Configure OIDC (issuer, client, redirect) | [OIDC / oauth2-proxy (EKS)](#oidc--oauth2-proxy-eks) |
| 6 | Sync secrets into the cluster | [Helm secrets (`secrets.mode`)](#helm-secrets-secretsmode) |
| 7 | Deploy the Helm chart | [Helm install](#helm-install) |
| 8 | Local dev without EKS | [Local OAuth stack (Docker Compose)](#local-oauth-stack-docker-compose) |
| 9 | Smoke test | [Verification](#verification) |

### GitHub App (organization)

RaSCaaS authenticates to GitHub as an **installation** of a **GitHub App**. You need:

- **App ID** — from the app’s settings page
- **Installation ID** — from the org install URL
- **Private key** — PEM generated once at app creation

The app calls the GitHub API to list installation repos, list branches, list workflows, dispatch `workflow_dispatch`, and poll Actions runs/jobs for the deploy UI.

#### 1. Create the app

1. In GitHub: **Organization → Settings → Developer settings → GitHub Apps → New GitHub App**.
2. **Basic settings**
   - **Name:** e.g. `kovr-rascaas-qa`
   - **Homepage URL:** RaSCaaS public URL (or internal docs URL)
   - **Webhook:** **Inactive** is fine — RaSCaaS polls Actions; no webhook handler is required today.
3. **Repository permissions**

   | Permission | Access | Why |
   |------------|--------|-----|
   | **Actions** | Read and write | List workflows, dispatch runs, read run/job status |
   | **Contents** | Read | Branch listing and workflow context |
   | **Metadata** | Read | Required for repository API access |

4. **Organization permissions:** none required for current RaSCaaS behavior.
5. **Subscribe to events:** none required (polling only).
6. **Where can this GitHub App be installed?** → **Only on this account** (your org).
7. Click **Create GitHub App**.
8. On the app page: **Generate a private key** and download the `.pem` file (only shown once).

#### 2. Install the app on the organization

1. **Install App** → select your organization.
2. Choose **All repositories** or **Only select repositories** (repos that contain your deploy workflow, e.g. platform and helm-charts).
3. After install, open the installation settings. The URL contains the installation id:

   `https://github.com/organizations/<org>/settings/installations/<INSTALLATION_ID>`

4. Note the **App ID** from the app’s **General** settings page.

#### 3. What this is not

| Approach | Used by RaSCaaS? |
|----------|------------------|
| Org-wide PAT / “account API key” | No |
| GitHub App + installation token | **Yes** |
| AWS account key for GitHub | No — AWS credentials are separate (IRSA + Secrets Manager for the PEM and OIDC secrets) |

Workflow runs still execute on **your** GitHub Actions runners with **their** AWS/GitHub credentials inside the workflow YAML. The App only **starts** the workflow and **reads** status for the UI.

### Workflow requirements

Each target repository must expose a dispatchable workflow:

- File under `.github/workflows/` (default in config: `uat-deploy.yml` / `DEFAULT_WORKFLOW`)
- Trigger includes **`workflow_dispatch`**
- Runners available for that repo (self-hosted or GitHub-hosted per your platform)

RaSCaaS dispatches with `ref: <selected-branch>` and empty `inputs` unless you extend the API in `app/main.py`.

### Wire GitHub credentials

#### Local (Docker Compose)

In `.env` (see `.env.example`):

```env
GITHUB_APP_ID=<app-id>
GITHUB_INSTALLATION_ID=<installation-id>
GITHUB_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----"
DEFAULT_WORKFLOW=uat-deploy.yml
```

Leave `GITHUB_*` empty for mock repos/branches/SSE during UI-only local work.

#### EKS (production)

| Variable | Source |
|----------|--------|
| `GITHUB_APP_ID` | Helm `fastapi.env` in `helm/rascaas/values.yaml` |
| `GITHUB_INSTALLATION_ID` | Helm `fastapi.env` |
| `GITHUB_PRIVATE_KEY` | Kubernetes Secret key `github-private-key` in `fastapi-secrets` |

**`secrets.mode=csi-driver`:** create AWS Secrets Manager secret **`rascaas-secrets`** (see `helm/_crds/secrets/README.md` and `rascaas-secrets.example.json`):

```json
{
  "GITHUB_PRIVATE_KEY": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----\n",
  "OIDC_CLIENT_SECRET": "<your-idp-client-secret>",
  "OAUTH2_COOKIE_SECRET": "<32-byte-random-ascii>"
}
```

| SM key | Helm / K8s target |
|--------|-------------------|
| `GITHUB_PRIVATE_KEY` | `fastapi-secrets` → `github-private-key` |
| `OIDC_CLIENT_SECRET` | `oauth2proxy-secret` → `client-secret` |
| `OAUTH2_COOKIE_SECRET` | `oauth2proxy-secret` → `cookie-secret` |

`GITHUB_APP_ID` and `GITHUB_INSTALLATION_ID` stay in **Helm values** (not in SM). IRSA: `helm/_crds/secrets/iam-rascaas-secrets-reader-policy.json` on `rascaas-sa` / `oauth2proxy-sa`.

**`secrets.mode=plain`:** copy `helm/_crds/secrets/plain-secrets.example.yaml` → `plain-secrets.yaml`, fill `stringData`, `kubectl apply -f plain-secrets.yaml` before `helm install`.

### OIDC / oauth2-proxy (EKS)

RaSCaaS serves the UI through **oauth2-proxy** (OIDC login). FastAPI trusts oauth2-proxy headers (`TRUST_OAUTH2_PROXY_IDENTITY=true` on EKS). These values must be **consistent** across Helm and secrets:

| Setting | Where |
|---------|--------|
| **Issuer URL** | `fastapi.env.OIDC_ISSUER_URL` **and** `oauth2proxy.oidcIssuerUrl` — **must be identical** |
| **Client ID** | `fastapi.env.OIDC_CLIENT_ID` **and** `oauth2proxy.clientId` |
| **Client secret** | Kubernetes Secret `oauth2proxy-secret` key `client-secret` (`plain-secrets.yaml` or AWS SM) — **not** in Helm values |
| **Redirect URI** | `oauth2proxy.redirectUrl` = `https://<host>/oauth2/callback` |
| **App URL** | `fastapi.env.APP_BASE_URL` = `https://<host>` |

For QA (`https://rascaas.qa.kovr.ai`), edit [`helm/_values/qa-install-values.yaml`](helm/_values/qa-install-values.yaml) for issuer, client ID, and redirect; put the client secret in `plain-secrets.yaml`.

#### AWS Cognito (QA)

Other QA workloads in this account use **Amazon Cognito** in `us-west-2`. RaSCaaS uses the same pattern.

**1. Find the issuer URL**

Format:

```text
https://cognito-idp.<region>.amazonaws.com/<user-pool-id>
```

QA pool for RaSCaaS (`qa-kovr-pool`):

```text
https://cognito-idp.us-west-2.amazonaws.com/us-west-2_R0hOOoYBb
```

| Field | Value |
|-------|--------|
| Pool name | `qa-kovr-pool` |
| User pool ID | `us-west-2_R0hOOoYBb` |
| ARN | `arn:aws:cognito-idp:us-west-2:650251729525:userpool/us-west-2_R0hOOoYBb` |

Console: **Amazon Cognito → User pools → *your pool* → User pool overview** — the issuer is shown as the OIDC issuer URL.

CLI (`qa-kovr` profile):

```bash
export AWS_PROFILE=qa-kovr
export AWS_REGION=us-west-2
export POOL_ID=us-west-2_R0hOOoYBb   # qa-kovr-pool

echo "https://cognito-idp.${AWS_REGION}.amazonaws.com/${POOL_ID}"
```

**2. Create or select an app client for RaSCaaS**

Console: **User pool → App integration → App clients → Create app client**

| Setting | Value |
|---------|--------|
| App type | Traditional web application (or SPA if your standard) |
| OAuth 2.0 grant types | **Authorization code grant** |
| Allowed callback URLs | `https://rascaas.qa.kovr.ai/oauth2/callback` |
| Allowed sign-out URLs (optional) | `https://rascaas.qa.kovr.ai/` |
| OpenID Connect scopes | `openid`, `email` (add `profile` if needed) |
| Client secret | Generate a secret (required for oauth2-proxy) |

Copy the **Client ID** and **Client secret**.

**3. Set Helm values** (`helm/_values/qa-install-values.yaml`)

Set **the same issuer** in both places:

```yaml
fastapi:
  env:
    OIDC_ISSUER_URL: "https://cognito-idp.us-west-2.amazonaws.com/us-west-2_R0hOOoYBb"
    OIDC_CLIENT_ID: "<your-cognito-app-client-id>"
    APP_BASE_URL: "https://rascaas.qa.kovr.ai"

oauth2proxy:
  oidcIssuerUrl: "https://cognito-idp.us-west-2.amazonaws.com/us-west-2_R0hOOoYBb"
  clientId: "<your-cognito-app-client-id>"
  redirectUrl: "https://rascaas.qa.kovr.ai/oauth2/callback"
```

**4. Set the client secret in Kubernetes** (not Helm)

Put the Cognito app client secret in `oauth2proxy-secret` → `client-secret`:

```bash
# Option A: add to .env then regenerate
#   OAUTH2_PROXY_CLIENT_SECRET=<cognito-client-secret>
python3 scripts/render-plain-secrets.py
kubectl apply -f helm/_crds/secrets/plain-secrets.yaml

# Option B: edit helm/_crds/secrets/plain-secrets.yaml stringData.client-secret directly
```

Do **not** use the local Docker Keycloak value (`rascaas-local-client-secret`) on EKS.

**5. Redeploy**

```bash
helm upgrade --install rascaas ./helm/rascaas -n rascaas \
  -f helm/_values/qa-install-values.yaml
```

**6. Verify**

- Browser: open `https://rascaas.qa.kovr.ai` → redirect to Cognito → back to the app after login.
- If login fails: check oauth2-proxy logs (`kubectl logs -n rascaas -l app.kubernetes.io/component=oauth2-proxy`) for redirect URI mismatch or invalid client secret.
- Cognito callback URL must match **exactly** (scheme, host, path): `https://rascaas.qa.kovr.ai/oauth2/callback`.

#### Other IdPs (Keycloak, etc.)

Use the IdP’s **OIDC issuer** URL (e.g. `https://<keycloak-host>/realms/<realm>`) in both `OIDC_ISSUER_URL` and `oauth2proxy.oidcIssuerUrl`. Register the same callback URL on the client. Local Docker Keycloak settings are in [Local OAuth stack](#local-oauth-stack-docker-compose) only.

### EKS prerequisites

**Full step-by-step (CRDs, gateway, secrets, Helm):** [`helm/_crds/README.md`](helm/_crds/README.md)

Your errors (`no matches for kind "Gateway"` / `TargetGroupConfiguration`) mean **step 1 below was skipped** — install Gateway API CRDs before applying RaSCaaS gateway YAML.

1. **Kubernetes context** — `kubectl config get-contexts` then `kubectl config use-context <real-name>` (not `your-eks-context`).

2. **Gateway API CRDs (cluster, once)** — required before `helm/_crds/gateway/*.yaml`. Run with `kubectl` pointed at the cluster:

```bash
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.2.2/config/crd/gateway/gateway-crds.yaml"
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.2.2/config/crd/gateway/gatewayclass.yaml"
kubectl get crd | grep -E 'gateway|targetgroup|loadbalancer'
kubectl get gatewayclass alb
```

If the AWS Load Balancer Controller was already running, restart it after CRDs are installed:

```bash
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
```

**Optional:** If this cluster already uses Kovr `grommet/helm-support`, you can run `./install-gateway-class.sh` instead of the URLs above. See [`helm/_crds/README.md`](helm/_crds/README.md).

3. `helm/_crds/namespace.yaml`
4. Service accounts: `helm/_crds/service-accounts/` (IRSA optional for `secrets.mode=plain`)
5. Secrets:
   - **plain:** `plain-secrets.yaml` (`python3 scripts/render-plain-secrets.py`)
   - **csi-driver:** `helm/_crds/secrets/spc.yaml`
6. Gateway: `helm/_crds/gateway/rascaas-gateway-base.yaml` + HTTPS template (hostname + IAM cert ARN)
7. Helm chart (see below)

Complete [OIDC / oauth2-proxy (EKS)](#oidc--oauth2-proxy-eks) before Helm if using Cognito or another IdP.

### Helm install

**QA overlay** (`https://rascaas.qa.kovr.ai`): [`helm/_values/qa-install-values.yaml`](helm/_values/qa-install-values.yaml) — Gateway: [`helm/_crds/gateway/rascaas-gateway-https.qa.yaml`](helm/_crds/gateway/rascaas-gateway-https.qa.yaml). Cognito per [OIDC / oauth2-proxy (EKS)](#oidc--oauth2-proxy-eks).

```bash
helm upgrade --install rascaas ./helm/rascaas -n rascaas \
  -f helm/_values/qa-install-values.yaml
```

Generic examples:

```bash
# Production — AWS Secrets Manager + CSI
helm upgrade --install rascaas ./helm/rascaas -n rascaas \
  --set secrets.mode=csi-driver \
  --set secrets.secretProviderClass=rascaas-secrets-provider \
  --set fastapi.env.GITHUB_APP_ID="<app-id>" \
  --set fastapi.env.GITHUB_INSTALLATION_ID="<installation-id>"

# Dev / no CSI — plain Kubernetes secrets
helm upgrade --install rascaas ./helm/rascaas -n rascaas \
  --set secrets.mode=plain
```

See [Helm secrets (`secrets.mode`)](#helm-secrets-secretsmode) for how CSI vs plain secrets are mounted.

### Verification

**Local**

```bash
cd platform-testing/RasCaaS
cp .env.example .env
# set GITHUB_* then:
docker compose up --build
```

Open http://localhost:4180 — repo and branch dropdowns should list real installation repos; **Deploy** should create a `workflow_dispatch` run in GitHub Actions.

**EKS**

1. Pods mount CSI volume only when `secrets.mode=csi-driver`.
2. `kubectl get secret fastapi-secrets oauth2proxy-secret -n rascaas` — keys present after CSI sync.
3. Hit the app through the gateway + oauth2-proxy; confirm dispatch in the target repo’s Actions tab.

### Quick reference — permissions vs APIs

| UI / behavior | GitHub API | App permission |
|---------------|------------|----------------|
| Repo dropdown | `GET /installation/repositories` | App installed on org with repo access |
| Branch dropdown | `GET /repos/{owner}/{repo}/branches` | Metadata (+ Contents read) |
| Deploy button | `POST .../actions/workflows/{file}/dispatches` | Actions read and write |
| Live status / SSE | `GET .../actions/runs`, `.../jobs` | Actions read (included in read/write) |
