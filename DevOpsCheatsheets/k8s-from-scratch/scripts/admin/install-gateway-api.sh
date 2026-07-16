#!/usr/bin/env bash
set -euo pipefail

GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.6.0}"
NGF_CHART_VERSION="${NGF_CHART_VERSION:-2.6.6}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALUES="${ROOT}/k8s/admin/nginx-gateway-fabric-values.yaml"

if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --namespace nginx-gateway --create-namespace \
  --version "${NGF_CHART_VERSION}" \
  --values "${VALUES}" \
  --wait --timeout 300s

kubectl wait --for=condition=Accepted gatewayclass/nginx --timeout=180s
kubectl -n nginx-gateway get pods,svc -o wide
echo "GatewayClass nginx ready. Gateway dataplane Service=LoadBalancer (MetalLB VIP 192.168.56.200)."
echo "Browse after make app: make browse  → https://localhost:8443/"
