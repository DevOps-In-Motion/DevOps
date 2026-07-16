#!/usr/bin/env bash
set -euo pipefail

# Admin: issue nginx-deployer client cert + kubeconfig under scripts/nginx/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_DIR="$(cd "${SCRIPT_DIR}/../nginx" && pwd)"
mkdir -p "${NGINX_DIR}"

KEY="${NGINX_DIR}/nginx-deployer.key"
CSR="${NGINX_DIR}/nginx-deployer.csr"
CRT="${NGINX_DIR}/nginx-deployer.crt"
KCFG="${NGINX_DIR}/nginx-deployer.kubeconfig"
CA_CERT="${NGINX_DIR}/cluster-ca.crt"

openssl genrsa -out "${KEY}" 2048
openssl req -new -key "${KEY}" -out "${CSR}" -subj "/CN=nginx-deployer/O=nginx-deployers"

CSR_BASE64=$(base64 < "${CSR}" | tr -d '\n')
kubectl delete csr nginx-deployer-csr --ignore-not-found
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: nginx-deployer-csr
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800
  usages:
    - client auth
EOF
kubectl certificate approve nginx-deployer-csr

# Signer may lag a few seconds after Approved.
for _ in $(seq 1 30); do
  cert_b64="$(kubectl get csr nginx-deployer-csr -o jsonpath='{.status.certificate}' 2>/dev/null || true)"
  if [[ -n "${cert_b64}" ]]; then
    echo "${cert_b64}" | base64 -d > "${CRT}"
    break
  fi
  sleep 1
done
[[ -s "${CRT}" ]] || { echo "error: empty cert after approve (timed out)" >&2; exit 1; }

if [[ -r /etc/kubernetes/pki/ca.crt ]]; then
  sudo cp /etc/kubernetes/pki/ca.crt "${CA_CERT}"
  sudo chown "$(id -u):$(id -g)" "${CA_CERT}"
else
  kubectl config view --raw \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "${CA_CERT}"
fi

kubectl config set-cluster kubernetes \
  --server="https://192.168.56.101:6443" \
  --certificate-authority="${CA_CERT}" --embed-certs=true --kubeconfig="${KCFG}"
kubectl config set-credentials nginx-deployer \
  --client-certificate="${CRT}" --client-key="${KEY}" --embed-certs=true --kubeconfig="${KCFG}"
kubectl config set-context nginx-deployer-context \
  --cluster=kubernetes --namespace=nginx-app --user=nginx-deployer --kubeconfig="${KCFG}"
kubectl config use-context nginx-deployer-context --kubeconfig="${KCFG}"

echo "Wrote ${KCFG}"
echo
echo "Next on Mac:"
echo "  make deployer-context   # kubectl config use-context nginx-deployer-context"
echo "  make app                # deploy into nginx-app AS nginx-deployer"
