#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CSR_BASE64=$(base64 < "${SCRIPT_DIR}/nginx-deployer.csr" | tr -d '\n')

cat <<EOF | kubectl --context=kubernetes-admin@kubernetes apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: nginx-deployer-csr
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800   # 7 days — adjust as needed
  usages:
    - client auth
EOF

kubectl --context=kubernetes-admin@kubernetes get csr
kubectl --context=kubernetes-admin@kubernetes certificate approve nginx-deployer-csr
