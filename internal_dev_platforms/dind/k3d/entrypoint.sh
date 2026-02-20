#!/usr/bin/env bash
# Create a k3d cluster and install the wiki Helm chart.
# DinD (intended): docker run --privileged --cgroupns=host -p 8080:8080 -p 8443:8443 wiki-k3d-dind  (no socket)
# Fallback:        docker run -v /var/run/docker.sock:/var/run/docker.sock wiki-k3d

set -e
exec 2>&1

CLUSTER_NAME="${K3D_CLUSTER_NAME:-wiki}"
RELEASE_NAME="${HELM_RELEASE_NAME:-wiki}"
NAMESPACE="${HELM_NAMESPACE:-default}"
CHART_DIR="/app/wiki-chart"
VALUES_FILE="${VALUES_FILE:-/app/k3d/values.yaml}"

# Pre-check: chart, values, and config exist (fail fast before cluster create)
if [[ ! -d "$CHART_DIR" ]]; then echo "ERROR: Chart dir missing: $CHART_DIR"; exit 1; fi
if [[ ! -f "$VALUES_FILE" ]]; then echo "ERROR: Values file missing: $VALUES_FILE"; exit 1; fi
K3D_CONFIG="${K3D_CONFIG:-/app/k3d/config.yaml}"
if [[ ! -f "$K3D_CONFIG" ]]; then echo "ERROR: k3d config missing: $K3D_CONFIG"; exit 1; fi

# Persistence (Option 1): if host volume is mounted at /data, ensure Postgres dir exists for k3d volume mapping
if [[ -d /data ]]; then
  mkdir -p /data/wiki-postgres
  echo "Using /data/wiki-postgres for Postgres persistence (restart-safe)."
fi

# --- Step 1: Create cluster from config (Traefik enabled). Servers memory 4G. Port 80 -> host 8080.
# Step 1 often hangs in DinD; we timeout after 5 min.
echo "=== [1/3] Creating k3d cluster from config (timeout 5 min) ==="
CLUSTER_CREATE_TIMEOUT=300
k3d cluster create --config "$K3D_CONFIG" &
K3D_PID=$!
K3D_START=$(date +%s)
while kill -0 "$K3D_PID" 2>/dev/null; do
  ELAPSED=$(($(date +%s) - K3D_START))
  if [ "$ELAPSED" -ge "$CLUSTER_CREATE_TIMEOUT" ]; then
    kill "$K3D_PID" 2>/dev/null; wait "$K3D_PID" 2>/dev/null
    echo "ERROR: k3d cluster create did not finish in ${CLUSTER_CREATE_TIMEOUT}s (step 1 hung)."
    echo "  Try again with more Docker memory; run with --privileged and do not use the Docker socket."
    exit 1
  fi
  echo "  ... cluster create in progress (${ELAPSED}s)"
  sleep 15
done
wait "$K3D_PID" || { echo "ERROR: k3d cluster create failed."; exit 1; }

# Verify cluster exists and print status
echo ""
echo "=== Checking cluster creation ==="
if ! k3d cluster list 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
  echo "ERROR: Cluster '$CLUSTER_NAME' not found after create. k3d cluster list:"
  k3d cluster list 2>/dev/null || true
  exit 1
fi
echo "Cluster '$CLUSTER_NAME' created successfully."
k3d cluster list 2>/dev/null || true

echo ""
echo "=== Waiting for API server (up to 120s) ==="
export KUBECONFIG="$(k3d kubeconfig write $CLUSTER_NAME)"
for i in $(seq 1 24); do
  if kubectl get nodes --request-timeout=5s 2>/dev/null | grep -q Ready; then
    echo "API server is reachable."
    break
  fi
  if [ "$i" -eq 24 ]; then
    echo "ERROR: Cluster did not become ready in time."
    echo "  Run ./k3d/debug-k3d-cluster.sh for details."
    exit 1
  fi
  echo "  attempt $i/24..."
  sleep 5
done

echo ""
echo "=== Cluster is up and running ==="
kubectl get nodes -o wide 2>/dev/null || true
echo ""

# Pre-load images into the cluster so pods start in seconds instead of 20+ min (DinD node pulls are slow).
# Pull into inner Docker, then k3d import copies them to nodes; Helm deploy then finds them already there.
if [[ -z "${SKIP_IMAGE_PRELOAD:-}" ]]; then
  WIKI_IMAGE="${WIKI_IMAGE:-public.ecr.aws/i3h9f2j0/demos/wiki-backend:latest}"
  POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:15}"
  echo "=== Pre-loading images into cluster (avoids slow per-pod pull) ==="
  echo "  Pulling $WIKI_IMAGE and $POSTGRES_IMAGE..."
  docker pull "$WIKI_IMAGE" && docker pull "$POSTGRES_IMAGE" || true
  echo "  Importing into cluster $CLUSTER_NAME..."
  k3d image import -c "$CLUSTER_NAME" "$WIKI_IMAGE" "$POSTGRES_IMAGE" 2>/dev/null || true
  echo ""
fi

# --- Step 2: Install wiki-chart (dependencies vendored in wiki-chart/charts/). Ingress: install nginx or re-enable Traefik.
echo "=== [2/3] Installing wiki-chart (release: $RELEASE_NAME). This may take 5–10 minutes. ==="
echo "  To debug from another terminal:  docker exec -it wiki-k3d-dind sh"
echo "  Then inside:  kubectl describe pod <name> -n $NAMESPACE  ;  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo ""
# Background: print pod status every 60s so you can see progress or why it's stuck (Helm --wait is silent)
PROG_PID=""
trap '[[ -n "$PROG_PID" ]] && kill "$PROG_PID" 2>/dev/null' EXIT
( for i in $(seq 1 20); do sleep 60; echo ""; echo "  --- pod status ($i min) ---"; kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -20 || true; done ) &
PROG_PID=$!
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "$VALUES_FILE" \
  --wait \
  --timeout=15m
kill "$PROG_PID" 2>/dev/null; PROG_PID=""

# --- Step 3: Verify wiki-backend is actually ready and API responds (don't report success if it didn't work)
echo "=== [3/3] Verifying wiki-backend is ready ==="
BACKEND_LABEL="app.kubernetes.io/name=backend"
VERIFY_TIMEOUT=120
VERIFY_START=$(date +%s)
while true; do
  READY=$(kubectl get pods -n "$NAMESPACE" -l "$BACKEND_LABEL" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "$READY" == "True" ]]; then
    echo "Wiki-backend pod is Ready."
    break
  fi
  ELAPSED=$(($(date +%s) - VERIFY_START))
  if [ "$ELAPSED" -ge "$VERIFY_TIMEOUT" ]; then
    echo ""
    echo "ERROR: Wiki-backend did not become Ready within ${VERIFY_TIMEOUT}s. Install may have 'finished' but the app is not running."
    echo ""
    echo "Pod status:"
    kubectl get pods -n "$NAMESPACE" -l "$BACKEND_LABEL" -o wide 2>/dev/null || true
    echo ""
    echo "Pod events (why it's stuck):"
    POD=$(kubectl get pods -n "$NAMESPACE" -l "$BACKEND_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$POD" ]]; then kubectl describe pod "$POD" -n "$NAMESPACE" 2>/dev/null | tail -30; fi
    echo ""
    echo "Recent cluster events:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -15
    exit 1
  fi
  echo "  Waiting for wiki-backend to be Ready (${ELAPSED}s)..."
  sleep 10
done

echo ""
echo "=== Done. ==="
echo ""
echo "  Traefik (K3s default). Endpoints on port 8080:"
echo "  API:        http://localhost:8080/users  http://localhost:8080/posts"
echo "  Grafana:    http://localhost:8080/grafana  (admin / admin)"
echo "  Kubeconfig: k3d kubeconfig merge $CLUSTER_NAME"
echo "  Stop:       k3d cluster delete $CLUSTER_NAME"
echo ""
