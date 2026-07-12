#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRT="${SCRIPT_DIR}/nginx-deployer.crt"
KEY="${SCRIPT_DIR}/nginx-deployer.key"

if [[ ! -s "${CRT}" ]]; then
  echo "error: missing or empty ${CRT}" >&2
  echo "Run scripts/post-csr.sh first (CSR must be approved)." >&2
  exit 1
fi
if [[ ! -s "${KEY}" ]]; then
  echo "error: missing or empty ${KEY}" >&2
  exit 1
fi

kubectl config set-credentials nginx-deployer \
  --client-certificate="${CRT}" \
  --client-key="${KEY}" \
  --embed-certs=true

kubectl config set-context nginx-deployer-context \
  --cluster=kubernetes \
  --namespace=nginx-app \
  --user=nginx-deployer

echo "Added nginx-deployer credentials and context to ~/.kube/config"
echo "Switch with: kubectl config use-context nginx-deployer-context"
