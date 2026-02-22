# Wiki API (Nebula Aurora Assignment)

This repo contains a Wiki API service (FastAPI + PostgreSQL) and a Helm chart to run it on Kubernetes. You can run the service in two ways:

1. **Helm chart** — install the chart into an existing cluster (e.g. minikube, kind, or k3d you created yourself).
2. **k3d + root Dockerfile** — use the root Dockerfile to build an image that creates a k3d cluster and installs the chart inside a container.

---

## 1. Run the service using the Helm chart

**Prerequisites:** Docker, [Helm](https://helm.sh/docs/intro/install/), [kubectl](https://kubernetes.io/docs/tasks/tools/), and a Kubernetes cluster (e.g. [minikube](https://minikube.sigs.k8s.io/), [kind](https://kind.sigs.k8s.io/), or [k3d](https://k3d.io/)).

### Install into your cluster

From the **repo root**:

```bash
# 1. Update chart dependencies (postgresql, kube-prometheus-stack, etc.)
cd wiki-chart && helm dependency update && cd ..

# 2. Install the chart (choose one of the options below)
```

**Option A — Minimal (app + Postgres sidecar, no Prometheus/Grafana):**

```bash
helm upgrade --install wiki ./wiki-chart \
  --namespace default \
  --create-namespace \
  -f ./testing/helm-test-values-min.yaml \
  --wait --timeout 10m
```

**Option B — Full stack (with PostgreSQL subchart, Prometheus operator in monitoring namespace):**

```bash
helm upgrade --install wiki-api ./wiki-chart \
  --namespace monitoring \
  --create-namespace \
  -f ./testing/helm-test-values-full.yaml \
  --wait --timeout 10m
```

**Option C — Use the install script:**

```bash
./testing/install-wiki-chart.sh
```

The script uses `testing/helm-test-values.yaml` by default. If that file is missing, edit the script to use `testing/helm-test-values-full.yaml` instead, or run the Option B command above.

### Access the API

- **If Ingress is enabled** and your cluster exposes port 80 (e.g. minikube `minikube addons enable ingress`, or nginx ingress installed):  
  `http://<ingress-host>/users`, `http://<ingress-host>/posts`
- **Otherwise, port-forward:**

  ```bash
  kubectl port-forward svc/wiki-api-service 8080:8080
  ```

  Then: `http://localhost:8080/users`, `http://localhost:8080/posts`, `http://localhost:8080/health`

### Grafana (when Prometheus stack is enabled)

The stack runs in the **monitoring** namespace. Port-forward the Grafana service (stock name `prometheus-operator-grafana`):

```bash
kubectl port-forward -n monitoring svc/prometheus-operator-grafana 3000:80
```

Open: `http://localhost:3000` (default login `admin` / `admin`). Dashboard: **Dashboards → creation** (uid `creation-dashboard-678`).

### Test the Helm chart

You can validate and test the chart without or with a running cluster.

**1. Lint and template (no cluster needed)**

From the **repo root**:

```bash
# Lint the chart
helm lint ./wiki-chart

# Update dependencies and render all templates (catches missing deps and template errors)
cd wiki-chart && helm dependency update && cd ..
helm template wiki ./wiki-chart -f ./testing/helm-test-values-min.yaml --debug
```

Use `-f ./testing/helm-test-values-full.yaml` if you want to test with the full stack values.

**2. Run Helm tests (cluster required, after install)**

The chart includes a test pod that hits the wiki service `/health` endpoint. After you have installed the release (e.g. `wiki` in `default`):

```bash
helm test wiki --namespace default
```

If the release or namespace is different, use the same name and namespace as your install. The test runs a short-lived pod that calls the wiki API; it should exit successfully.

---

## 2. Run the service using k3d and the root Dockerfile

The **root `Dockerfile`** builds an image that:

- Installs **k3d**, **kubectl**, and **Helm** inside the container
- Creates a k3d cluster (with Traefik disabled so nginx ingress can use 80/443)
- Installs **ingress-nginx** and then the **wiki-chart** with `k3d/values.yaml`

You run this image with the host Docker socket so the container can create the k3d cluster on your machine. No local kubectl or Helm required.

**Prerequisites:** Docker (with access to `/var/run/docker.sock`).

### Build and run

From the **repo root**:

```bash
# Build the image (includes wiki-chart and k3d entrypoint)
docker build -t wiki-k3d .

# Run: creates k3d cluster and installs the wiki stack (may take 5–10 minutes)
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wiki-k3d
```

When it finishes, you’ll see:

- **API:** `http://localhost/users`, `http://localhost/posts`
- **Grafana:** `http://localhost/grafana/d/creation-dashboard-678/creation` (admin / admin)

### Optional environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `K3D_CLUSTER_NAME` | `wiki` | k3d cluster name |
| `HELM_RELEASE_NAME` | `wiki` | Helm release name |
| `HELM_NAMESPACE` | `default` | Namespace for the wiki release |
| `SKIP_DISABLE_TRAEFIK` | (unset) | Set to `1` if cluster creation hangs when disabling Traefik (Traefik and nginx will both run) |

Example:

```bash
docker run --rm -it \
  -e SKIP_DISABLE_TRAEFIK=1 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  wiki-k3d
```

### Use kubectl on the cluster from the host (optional)

After the container has created the cluster:

```bash
k3d kubeconfig merge wiki
kubectl get pods -A
```

### Stop and remove the cluster

```bash
k3d cluster delete wiki
```

(Use the same name as `K3D_CLUSTER_NAME` if you changed it.)
