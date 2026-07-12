#!/usr/bin/env bash
set -euo pipefail

# Installs cert-manager via the official Helm chart (cluster-admin).
# Requires: helm, kubectl
#
# Tolerates the control-plane taint so controllers can schedule when
# workers are dedicated (e.g. workload=nginx:NoSchedule).

CHART_VERSION="${CERT_MANAGER_CHART_VERSION:-v1.17.2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALUES="${ROOT}/k8s/cert-manager-values.yaml"

helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "${VALUES}" \
  --wait \
  --timeout 180s

echo "cert-manager ready. Next: kubectl apply -f k8s/nginx-ssl-ing.yaml"
echo "Uninstall later with: helm uninstall cert-manager -n cert-manager && kubectl delete ns cert-manager"
