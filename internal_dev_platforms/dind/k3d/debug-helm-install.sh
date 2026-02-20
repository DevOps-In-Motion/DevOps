#!/usr/bin/env bash
# Debug script to run in another terminal while entrypoint.sh is running (e.g. during helm install).
#
# From host (DinD):   ./k3d/debug-helm-install.sh   # finds wiki-k3d-dind container, runs inside, then prints exec command
# From host (socket): export KUBECONFIG=$(k3d kubeconfig write wiki); ./k3d/debug-helm-install.sh
# Inside container:   export KUBECONFIG=$(k3d kubeconfig write wiki); /app/k3d/debug-helm-install.sh
#
# Optional: NAMESPACE=default CLUSTER_NAME=wiki (defaults shown).

set -e

CLUSTER_NAME="${K3D_CLUSTER_NAME:-wiki}"
NAMESPACE="${HELM_NAMESPACE:-default}"

# When run from host: if no cluster visible, find DinD container and re-run this script inside it
if ! command -v k3d &>/dev/null || ! k3d cluster list 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
  # Prefer exact container name (set by test-k3d.sh / README), then image
  WIKI_K3D_CONTAINER=$(docker ps -q --filter "name=^wiki-k3d-dind$" 2>/dev/null | head -1)
  if [[ -z "$WIKI_K3D_CONTAINER" ]]; then
    WIKI_K3D_CONTAINER=$(docker ps -q --filter "ancestor=wiki-k3d-dind" 2>/dev/null | head -1)
  fi
  if [[ -n "$WIKI_K3D_CONTAINER" ]]; then
    export WIKI_K3D_CONTAINER
    echo "DinD container found: $WIKI_K3D_CONTAINER. Running debug inside container..."
    echo ""
    docker exec "$WIKI_K3D_CONTAINER" /app/k3d/debug-helm-install.sh
    echo ""
    echo "To get a shell inside the container: docker exec -it $WIKI_K3D_CONTAINER sh"
    exit 0
  fi
  echo "Cannot reach cluster and no running wiki-k3d-dind container found."
  echo "Start the cluster first: docker run --rm -it --privileged --cgroupns=host -p 8080:8080 -p 8443:8443 -v wiki-data:/data wiki-k3d-dind"
  exit 1
fi

# Use k3d kubeconfig if KUBECONFIG not set (e.g. when running inside the image)
if [[ -z "${KUBECONFIG:-}" ]] && command -v k3d &>/dev/null; then
  export KUBECONFIG="$(k3d kubeconfig write "$CLUSTER_NAME" 2>/dev/null)"
fi

if ! kubectl cluster-info &>/dev/null; then
  echo "Cannot reach cluster. Set KUBECONFIG or run where k3d/kubectl can see cluster $CLUSTER_NAME."
  exit 1
fi

echo "=== Nodes ==="
kubectl get nodes -o wide 2>/dev/null || true

echo ""
echo "=== Pods (namespace: $NAMESPACE) ==="
kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || true

echo ""
echo "=== Recent events (namespace: $NAMESPACE) ==="
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -25

NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -v "Running\|Completed" || true)
if [[ -n "$NOT_READY" ]]; then
  echo ""
  echo "=== Not-ready pods (describe) ==="
  while read -r line; do
    pod=$(echo "$line" | awk '{print $1}')
    [[ -z "$pod" ]] && continue
    echo "--- $pod ---"
    kubectl describe pod "$pod" -n "$NAMESPACE" 2>/dev/null | tail -40
  done <<< "$NOT_READY"
fi

echo ""
echo "=== PVCs (namespace: $NAMESPACE) ==="
kubectl get pvc -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "=== Helm release status ==="
helm list -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "--- To get logs of a failing pod: kubectl logs <pod> -n $NAMESPACE [-c <container>] ---"
