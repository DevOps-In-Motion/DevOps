#!/usr/bin/env bash
# Apply OIDC apiserver flags via kubeadm (durable — regenerates static Pod from
# ClusterConfiguration). Does NOT sed/patch /etc/kubernetes/manifests by hand.
#
# First-time / recreate: OIDC is baked in by scripts/vm-controlplane-init.sh.
#
# Existing control plane (after editing placeholders.env):
#   bash k8s/oidc/apiserver/render-kubeadm-oidc.sh
#   bash k8s/oidc/apiserver/apply-oidc-apiserver.sh
#
# Rollout: ONE control plane at a time; wait for readyz before the next.
# Keep certificate-based admin.conf until IdP + kubelogin work.

set -euo pipefail
OIDC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${OIDC_ENV_FILE:-${OIDC_ROOT}/placeholders.env}"
SSH_USER="${SSH_USER:-vagrant}"
RENDER="${OIDC_ROOT}/apiserver/render-kubeadm-oidc.sh"
GEN_CFG="${OIDC_ROOT}/apiserver/generated/clusterconfiguration-oidc.yaml"
GEN_CA="${OIDC_ROOT}/apiserver/generated/oidc-ca.crt"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
elif [[ -f "${OIDC_ROOT}/placeholders.env.example" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${OIDC_ROOT}/placeholders.env.example"
  set +a
fi

bash "${RENDER}"
[[ -f "${GEN_CFG}" ]] || { echo "error: missing ${GEN_CFG}" >&2; exit 1; }

: "${OIDC_CA_FILE:=/etc/kubernetes/pki/oidc-ca.crt}"
HOSTS="${CONTROL_PLANE_HOSTS:-}"
SSH_USER="${SSH_USER:-vagrant}"

install_ca_and_phase() {
  local host="$1"
  echo "==> ${host}: install OIDC CA + kubeadm init phase control-plane apiserver"

  scp -o StrictHostKeyChecking=no "${GEN_CA}" "${SSH_USER}@${host}:/tmp/oidc-ca.crt"
  scp -o StrictHostKeyChecking=no "${GEN_CFG}" "${SSH_USER}@${host}:/tmp/clusterconfiguration-oidc.yaml"

  ssh -o StrictHostKeyChecking=no "${SSH_USER}@${host}" \
    "sudo mkdir -p \"\$(dirname '${OIDC_CA_FILE}')\" && \
     sudo cp /tmp/oidc-ca.crt '${OIDC_CA_FILE}' && sudo chmod 644 '${OIDC_CA_FILE}' && \
     printf '%s\n' \
       'apiVersion: kubeadm.k8s.io/v1beta4' \
       'kind: InitConfiguration' \
       'localAPIEndpoint:' \
       '  advertiseAddress: \"192.168.56.101\"' \
       '  bindPort: 6443' \
       '---' | sudo tee /tmp/kubeadm-oidc-apply.yaml >/dev/null && \
     sudo cat /tmp/clusterconfiguration-oidc.yaml | sudo tee -a /tmp/kubeadm-oidc-apply.yaml >/dev/null && \
     sudo kubeadm init phase control-plane apiserver --config /tmp/kubeadm-oidc-apply.yaml"

  echo "waiting for apiserver readyz on ${host}..."
  local i
  for i in $(seq 1 60); do
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${host}" \
      "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get --raw=/readyz >/dev/null 2>&1"; then
      echo "ready: ${host}"
      ssh -o StrictHostKeyChecking=no "${SSH_USER}@${host}" \
        "sudo grep -E 'oidc-issuer-url|oidc-groups-prefix' /etc/kubernetes/manifests/kube-apiserver.yaml | head -5"
      return 0
    fi
    sleep 2
  done
  echo "error: apiserver not ready on ${host}" >&2
  return 1
}

apply_local() {
  echo "==> CP_LOCAL: kubeadm init phase control-plane apiserver"
  sudo mkdir -p "$(dirname "${OIDC_CA_FILE}")"
  sudo cp "${GEN_CA}" "${OIDC_CA_FILE}"
  sudo chmod 644 "${OIDC_CA_FILE}"
  local cfg=/tmp/kubeadm-oidc-apply.yaml
  {
    cat <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "192.168.56.101"
  bindPort: 6443
---
EOF
    cat "${GEN_CFG}"
  } >"${cfg}"
  sudo kubeadm init phase control-plane apiserver --config "${cfg}"
  echo "Done. Static Pod rewritten by kubeadm from ClusterConfiguration."
}

if [[ "${CP_LOCAL:-0}" == "1" ]]; then
  apply_local
  exit 0
fi

if [[ -z "${HOSTS}" ]]; then
  echo "error: set CONTROL_PLANE_HOSTS (in placeholders.env) or CP_LOCAL=1" >&2
  exit 1
fi

echo "Rolling kubeadm apiserver phase ONE control plane at a time."
echo "Keep admin.conf (client cert) available — do not rely on OIDC until IdP works."
for host in ${HOSTS}; do
  install_ca_and_phase "${host}"
done
echo "All control planes updated via kubeadm ClusterConfiguration."
