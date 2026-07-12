#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_CONTEXT="${ADMIN_CONTEXT:-kubernetes-admin@kubernetes}"

kubectl --context="${ADMIN_CONTEXT}" get csr nginx-deployer-csr \
  -o jsonpath='{.status.certificate}' | base64 -d > "${SCRIPT_DIR}/nginx-deployer.crt"

if [[ ! -s "${SCRIPT_DIR}/nginx-deployer.crt" ]]; then
  echo "error: nginx-deployer.crt is empty — is the CSR approved and issued?" >&2
  echo "  kubectl --context=${ADMIN_CONTEXT} get csr nginx-deployer-csr" >&2
  exit 1
fi

CLUSTER_NAME="kubernetes"
API_SERVER="https://192.168.56.101:6443"
CA_CERT="${SCRIPT_DIR}/cluster-ca.crt"

# Host machines do not have /etc/kubernetes/pki — pull CA from the admin kubeconfig.
kubectl config view --raw --context="${ADMIN_CONTEXT}" \
  -o jsonpath='{.clusters[?(@.name=="kubernetes")].cluster.certificate-authority-data}' \
  | base64 -d > "${CA_CERT}"

if [[ ! -s "${CA_CERT}" ]]; then
  echo "error: could not extract cluster CA from kubeconfig context ${ADMIN_CONTEXT}" >&2
  exit 1
fi

kubectl config set-cluster "${CLUSTER_NAME}" \
  --server="${API_SERVER}" \
  --certificate-authority="${CA_CERT}" \
  --embed-certs=true \
  --kubeconfig="${SCRIPT_DIR}/nginx-deployer.kubeconfig"

kubectl config set-credentials nginx-deployer \
  --client-certificate="${SCRIPT_DIR}/nginx-deployer.crt" \
  --client-key="${SCRIPT_DIR}/nginx-deployer.key" \
  --embed-certs=true \
  --kubeconfig="${SCRIPT_DIR}/nginx-deployer.kubeconfig"

kubectl config set-context nginx-deployer-context \
  --cluster="${CLUSTER_NAME}" \
  --namespace=nginx-app \
  --user=nginx-deployer \
  --kubeconfig="${SCRIPT_DIR}/nginx-deployer.kubeconfig"

kubectl config use-context nginx-deployer-context \
  --kubeconfig="${SCRIPT_DIR}/nginx-deployer.kubeconfig"

echo "Wrote ${SCRIPT_DIR}/nginx-deployer.kubeconfig"
echo "Merge into ~/.kube/config with: ${SCRIPT_DIR}/add-user-context.sh"
