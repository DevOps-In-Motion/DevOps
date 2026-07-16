#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f https://raw.githubusercontent.com/techiescamp/cka-certification-guide/refs/heads/main/lab-setup/manifests/metrics-server/metrics-server.yaml
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s
kubectl top nodes || echo "metrics warming up — retry: kubectl top nodes"
