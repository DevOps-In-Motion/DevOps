# k8s-from-scratch

3-node Kubernetes lab on Vagrant + VirtualBox: Calico, cert-manager, Gateway API (NGINX Gateway Fabric), HA nginx.

**Traffic:** client -> Gateway -> HTTPRoute -> Service -> Pods  
(MetalLB VIP `192.168.56.200` under the hood.)

Architecture:
[`docs/architecture.md`](docs/architecture.md) (overview) |
[`docs/architecture.excalidraw`](docs/architecture.excalidraw) (platform / AuthZ) |
[`docs/networking.excalidraw`](docs/networking.excalidraw) (Pod <-> Pod / Calico)

## Prerequisites

On the Mac host:

- VirtualBox 7+
- Vagrant 2.4+
- ~8 GB RAM free for the VMs
- `kubectl` (for `make deployer-context` / host-side checks)

Optional later: `ngrok` + auth token (`make share`).

## Bring-up (do these in order)

Run everything from the repo root.

### 1. Boot the cluster

```bash
make up
```

Creates the 3 VMs, installs CRI-O + kubeadm, initializes the control plane, and joins the workers. Takes several minutes the first time.

**Done when:** `vagrant status` shows all three VMs `running`.

### 2. Install platform (admin)

```bash
make admin
```

Runs on the control plane as cluster-admin: Calico, metrics-server, cert-manager + issuers, MetalLB, Gateway API / NGINX Gateway Fabric, `nginx-app` namespace + RBAC, and issues the `nginx-deployer` client cert / kubeconfig under `scripts/nginx/`.

**Done when:** the Makefile prints `=== Admin complete ===` and the next-step list.

### 3. Point your Mac kubectl at nginx-deployer

```bash
make deployer-context
```

Merges `scripts/nginx/nginx-deployer.kubeconfig` into `~/.kube/config` and switches to `nginx-deployer-context`.

Optional: `make context-host` first if you also want the **admin** context on the Mac (break-glass). Not required for the app.

**Done when:** `kubectl config current-context` is `nginx-deployer-context` and `kubectl auth whoami` shows `nginx-deployer`.

### 4. Deploy the app (as deployer, not admin)

```bash
make app
```

Applies `k8s/nginx/` into `nginx-app` using the deployer kubeconfig. Refuses to run as admin.

**Done when:** `make status` shows the Deployment, Service, Gateway, and HTTPRoute in `nginx-app`, and Gateway has address `192.168.56.200`.

### 5. Open the site

```bash
make browse
```

Starts a Vagrant SSH local forward (worker1 -> Gateway VIP:443) and opens **https://localhost:8443/**. No host Local Network privilege required.

**Done when:** the browser shows NYAN CAT (self-signed TLS; accept the warning).

### One-liner recreate

After a destroy, the full path is:

```bash
make up && make admin && make deployer-context && make app && make browse
```

## Verify

```bash
make status          # nodes + nginx-app resources + GatewayClass
make check-nginx     # in-cluster checks from the control plane
```

## Optional: public URL (ngrok)

```bash
# one-time: brew install ngrok/ngrok/ngrok && ngrok config add-authtoken <token>
make share           # prints a public https://*.ngrok-free.app URL
```

Starts the local browse tunnel if needed, then exposes it through ngrok. Not part of `make admin` / `make app`.

## Destroy / recreate

```bash
make destroy         # VMs + join artifacts + tunnel pid + deployer kubeconfig/certs
make up && make admin && make deployer-context && make app && make browse
```

Static site files (`k8s/nginx/static/{index.html,stars.gif,pirate.gif}`) live on the host and survive destroy via the `/vagrant` sync. Regenerating the starfield (optional): `bash scripts/nginx/generate-stars.sh`.

## Optional: OIDC (IdP-agnostic)

Placeholder OIDC `apiServer.extraArgs` are already set at `kubeadm init` (survive recreate). No Keycloak/Dex/Okta is installed — plug an IdP later via `k8s/oidc/placeholders.env`.

```bash
make oidc-render     # render kubeadm ClusterConfiguration OIDC
make oidc-rbac       # apply group RBAC (needs placeholders.env)
make oidc-policy     # Gatekeeper constraints (Gatekeeper must already be installed)
```

Gatekeeper is **not** installed by `make admin`; policies under `k8s/oidc/policy/` apply only after you install it yourself.

Full steps: [`k8s/oidc/README.md`](k8s/oidc/README.md) · [`k8s/oidc/docs/README.md`](k8s/oidc/docs/README.md).

## Layout

| Who | Paths | Does |
| --- | --- | --- |
| Admin | `scripts/admin/`, `k8s/admin/` | Cluster platform + `nginx-app` RBAC + deployer cert |
| nginx-deployer | `scripts/nginx/`, `k8s/nginx/` | App only inside `nginx-app` |
| OIDC | `k8s/oidc/` | Durable kubeadm OIDC + group RBAC + Gatekeeper policies (IdP later) |

## VMs

| VM | IP | Role |
| --- | --- | --- |
| controlplane | 192.168.56.101 | API / etcd |
| worker1 | 192.168.56.102 | Workloads |
| worker2 | 192.168.56.103 | Workloads |

## Common commands

```bash
make status
make check-nginx
make context-host        # admin kubeconfig on Mac
make deployer-context    # nginx-deployer on Mac
make destroy
```

## Versions (tested)

Kubernetes v1.36.2 | CRI-O 1.36 | Calico v3.31.3 | MetalLB v0.14.9 | cert-manager v1.17.2 | Gateway API v1.6.0 | NGINX Gateway Fabric 2.6.6
