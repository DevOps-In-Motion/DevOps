#!/usr/bin/env bash
# Install only the Helm-based supporting stack for the vanilla wiki installation:
#   - Prometheus + Grafana (kube-prometheus-stack)
#   - Creation dashboard ConfigMap (users/posts rate)
# Does NOT apply test-wiki-stack.yaml; apply that separately first.
#
# Usage (from repo root):
#   ./testing/install-helm-dep.sh
#   STACK_VALUES=testing/values-prometheus-stack.yaml ./testing/install-helm-dep.sh
#
# Default STACK_VALUES=values-prometheus-stack.yaml (includes wiki-api ServiceMonitor + Grafana config).
# Use prometheus-stack-wiki-values.yaml for minimal config (additionalScrapeConfigs only).
#
# Requires: helm, kubectl, cluster running. Vanilla stack (test-wiki-stack.yaml) applied first.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STACK_VALUES="${STACK_VALUES:-$SCRIPT_DIR/values-prometheus-stack.yaml}"
DASHBOARD_JSON="$REPO_ROOT/wiki-chart/dashboards/creation-dashboard.json"
NAMESPACE_MONITORING="${NAMESPACE_MONITORING:-monitoring}"
RELEASE_NAME="${RELEASE_NAME:-prometheus-stack}"

echo "=== 1. Helm: add repo for kube-prometheus-stack ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

echo ""
echo "=== 2. Install kube-prometheus-stack (Prometheus + Grafana) in namespace $NAMESPACE_MONITORING ==="
helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE_MONITORING" \
  --create-namespace \
  -f "$STACK_VALUES" \
  --wait \
  --timeout 10m

echo ""
echo "=== 3. Load creation dashboard into Grafana (ConfigMap with label for sidecar) ==="
kubectl create configmap creation-dashboard \
  --from-file=creation-dashboard.json="$DASHBOARD_JSON" \
  --namespace "$NAMESPACE_MONITORING" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap creation-dashboard grafana_dashboard=1 --namespace "$NAMESPACE_MONITORING" --overwrite

echo ""
echo "=== 4. Apply ServiceMonitor for wiki-api (so Prometheus scrapes wiki-api-service) ==="
kubectl apply -f "$SCRIPT_DIR/servicemonitor-wiki-api.yaml" -n "$NAMESPACE_MONITORING"
kubectl label servicemonitor prometheus-stack-wiki-api -n "$NAMESPACE_MONITORING" release="$RELEASE_NAME" --overwrite

echo ""
echo "=== Done. Helm dependencies installed for vanilla wiki stack. ==="
echo "  - Prometheus scrapes wiki-api-service.default.svc.cluster.local:8080/metrics"
echo "  - Grafana dashboard (users/posts creation rate): uid creation-dashboard-678"
echo ""
echo "  Access Grafana:"
echo "    kubectl port-forward -n $NAMESPACE_MONITORING svc/${RELEASE_NAME}-grafana 3000:80"
echo "    http://localhost:3000/grafana/d/creation-dashboard-678/creation (admin / admin)"
