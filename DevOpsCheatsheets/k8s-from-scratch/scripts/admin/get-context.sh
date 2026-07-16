#!/usr/bin/env bash
set -euo pipefail

# Admin (on Mac host): pull admin.conf into ~/.kube/config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT="${SCRIPT_DIR}/controlplane-kubeconfig.yaml"

cd "${REPO_ROOT}"
vagrant ssh controlplane -c "sudo cat /etc/kubernetes/admin.conf" > "${OUT}"

KUBECONFIG="${HOME}/.kube/config:${OUT}" kubectl config view --flatten > /tmp/merged-config
mv /tmp/merged-config "${HOME}/.kube/config"
chmod 600 "${HOME}/.kube/config"

kubectl config get-contexts
kubectl config use-context kubernetes-admin@kubernetes
echo "Merged admin kubeconfig into ~/.kube/config (also ${OUT})"
