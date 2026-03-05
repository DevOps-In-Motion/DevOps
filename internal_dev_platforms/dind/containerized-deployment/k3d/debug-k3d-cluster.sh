#!/usr/bin/env bash
# Check k3d cluster status (nodes, kube-system, loadbalancer, API). Use while cluster is starting or to verify health.
#
# From host (DinD):  ./k3d/debug-k3d-cluster.sh   # finds wiki-k3d-dind container, runs inside, then prints exec command
# From host (socket):  export KUBECONFIG=$(k3d kubeconfig write wiki); ./k3d/debug-k3d-cluster.sh
# Inside container:    export KUBECONFIG=$(k3d kubeconfig write wiki); /app/k3d/debug-k3d-cluster.sh
#
# Optional: CLUSTER_NAME=wiki

set -e

CLUSTER_NAME="${K3D_CLUSTER_NAME:-wiki}"

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
    docker exec "$WIKI_K3D_CONTAINER" /app/k3d/debug-k3d-cluster.sh
    echo ""
    echo "To get a shell inside the container: docker exec -it $WIKI_K3D_CONTAINER sh"
    exit 0
  fi
  echo "No k3d cluster named '$CLUSTER_NAME' and no running wiki-k3d-dind container found."
  exit 1
fi

# Use k3d kubeconfig if KUBECONFIG not set
if [[ -z "${KUBECONFIG:-}" ]] && command -v k3d &>/dev/null; then
  export KUBECONFIG="$(k3d kubeconfig write "$CLUSTER_NAME" 2>/dev/null)"
fi

echo "=== k3d cluster list ==="
k3d cluster list 2>/dev/null || true

echo ""
echo "=== Cluster API reachable? ==="
if kubectl cluster-info &>/dev/null; then
  kubectl cluster-info
else
  echo "Cannot reach API. Cluster '$CLUSTER_NAME' exists but API not ready yet (may still be starting)."
  exit 1
fi

echo ""
echo "=== Nodes ==="
kubectl get nodes -o wide 2>/dev/null || true

echo ""
echo "=== kube-system pods (Traefik, CoreDNS, etc.) ==="
kubectl get pods -n kube-system -o wide 2>/dev/null || true

echo ""
echo "=== Loadbalancer (Traefik ingress) ==="
kubectl get svc -n kube-system -l app.kubernetes.io/name=traefik 2>/dev/null || true

echo ""
echo "=== All kube-system services ==="
kubectl get svc -n kube-system 2>/dev/null || true
