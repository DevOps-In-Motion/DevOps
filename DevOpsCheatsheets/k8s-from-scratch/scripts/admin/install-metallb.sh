#!/usr/bin/env bash
set -euo pipefail

# MetalLB (L2) so Gateway can use Service type=LoadBalancer on 192.168.56.0/24.
METALLB_VERSION="${METALLB_VERSION:-v0.14.9}"

kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"
kubectl -n metallb-system wait --for=condition=Available deploy --all --timeout=300s
kubectl -n metallb-system wait --for=condition=ready pod --all --timeout=300s

# Webhook can lag a few seconds after pods Ready on a fresh cluster.
POOL=/vagrant/k8s/admin/metallb-pool.yaml
ok=0
for _ in $(seq 1 30); do
  if kubectl apply -f "${POOL}" 2>/dev/null; then
    ok=1
    break
  fi
  sleep 2
done
[[ "${ok}" == "1" ]] || kubectl apply -f "${POOL}"
kubectl -n metallb-system get ipaddresspool,l2advertisement
echo "MetalLB ready (pool 192.168.56.200-210)"
