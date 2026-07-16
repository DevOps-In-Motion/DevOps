#!/usr/bin/env bash
set -euo pipefail

# Mac host: add nginx-deployer to ~/.kube/config and switch to it.
# Run after: make admin  (and optionally make context-host for the admin context)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_DIR="$(cd "${SCRIPT_DIR}/../nginx" && pwd)"
CRT="${NGINX_DIR}/nginx-deployer.crt"
KEY="${NGINX_DIR}/nginx-deployer.key"
CA="${NGINX_DIR}/cluster-ca.crt"
KCFG="${NGINX_DIR}/nginx-deployer.kubeconfig"

[[ -s "${CRT}" && -s "${KEY}" ]] || {
  echo "error: missing cert/key — run make admin first" >&2
  exit 1
}

mkdir -p "${HOME}/.kube"

# Prefer the kubeconfig written by issue-deployer (has cluster + user + context).
if [[ -s "${KCFG}" ]]; then
  if [[ -s "${HOME}/.kube/config" ]]; then
    KUBECONFIG="${KCFG}:${HOME}/.kube/config" kubectl config view --flatten > /tmp/kubeconfig-merged
    mv /tmp/kubeconfig-merged "${HOME}/.kube/config"
  else
    cp "${KCFG}" "${HOME}/.kube/config"
  fi
  chmod 600 "${HOME}/.kube/config"
else
  [[ -s "${CA}" ]] || {
    echo "error: missing ${CA} — run make admin first" >&2
    exit 1
  }
  kubectl config set-cluster kubernetes \
    --server="https://192.168.56.101:6443" \
    --certificate-authority="${CA}" --embed-certs=true
  kubectl config set-credentials nginx-deployer \
    --client-certificate="${CRT}" --client-key="${KEY}" --embed-certs=true
  kubectl config set-context nginx-deployer-context \
    --cluster=kubernetes --namespace=nginx-app --user=nginx-deployer
fi

kubectl config use-context nginx-deployer-context
echo
echo "Current context: $(kubectl config current-context)"
kubectl auth whoami 2>/dev/null || true
echo
echo "Next: make app   # deploys into nginx-app as nginx-deployer"
