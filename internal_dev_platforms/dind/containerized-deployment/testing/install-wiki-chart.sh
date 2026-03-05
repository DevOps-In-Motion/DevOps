#!/usr/bin/env bash
# Install wiki-chart via Helm. Removes conflicting Ingress (wiki-api-ingress) if present
# so nginx admission webhook does not reject with "host _ and path /users is already defined".
# Run from repo root: ./testing/install-wiki-chart.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_DIR="$REPO_ROOT/wiki-chart"
VALUES="$SCRIPT_DIR/helm-test-values.yaml"
NAMESPACE="${NAMESPACE:-default}"
RELEASE="${RELEASE:-wiki}"

echo "=== Removing conflicting Ingress if present (wiki-api-ingress) ==="
kubectl delete ingress wiki-api-ingress -n "$NAMESPACE" 2>/dev/null || true

echo "=== Updating chart dependencies ==="
cd "$CHART_DIR"
helm dependency update
cd "$REPO_ROOT"

echo "=== Installing/upgrading $RELEASE from wiki-chart ==="
# Same as: helm install wiki ./wiki-chart -f ./testing/helm-test-values.yaml (with namespace + wait)
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "$VALUES" \
  --wait \
  --timeout 10m

echo ""
echo "Done. API: http://localhost/users  http://localhost/posts"
echo "Grafana: http://localhost/grafana/d/creation-dashboard-678/creation (admin / admin)"
