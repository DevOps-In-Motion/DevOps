#!/usr/bin/env bash
set -euo pipefail

# Admin: install cert-manager (cluster-scoped).
#   vagrant ssh controlplane -c 'bash /vagrant/scripts/admin/install-cert-manager.sh'

CHART_VERSION="${CERT_MANAGER_CHART_VERSION:-v1.17.2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALUES="${ROOT}/k8s/admin/cert-manager-values.yaml"

if [[ ! -f "${VALUES}" ]]; then
  echo "error: values file not found: ${VALUES}" >&2
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found; installing Helm 3..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "${VALUES}" \
  --wait \
  --timeout 300s

echo "Waiting for cert-manager-webhook endpoints..."
for _ in $(seq 1 60); do
  eps="$(kubectl -n cert-manager get endpoints cert-manager-webhook -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  if [[ -n "${eps}" ]]; then
    echo "webhook endpoints: ${eps}"
    break
  fi
  sleep 5
done
if [[ -z "${eps:-}" ]]; then
  echo "error: cert-manager-webhook has no endpoints." >&2
  echo "  Try: bash /vagrant/scripts/admin/fix-node-ips.sh" >&2
  kubectl -n cert-manager get pods -o wide >&2 || true
  exit 1
fi

kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=180s
echo "cert-manager ready (admin). Next: make platform-tls (ClusterIssuers)"
echo "Uninstall: helm uninstall cert-manager -n cert-manager && kubectl delete ns cert-manager"
