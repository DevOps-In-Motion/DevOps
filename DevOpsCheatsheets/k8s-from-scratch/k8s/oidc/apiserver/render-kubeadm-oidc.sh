#!/usr/bin/env bash
# Render durable kubeadm ClusterConfiguration (OIDC extraArgs) from placeholders.
#   cp k8s/oidc/placeholders.env.example k8s/oidc/placeholders.env
#   bash k8s/oidc/apiserver/render-kubeadm-oidc.sh

set -euo pipefail
OIDC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${OIDC_ENV_FILE:-${OIDC_ROOT}/placeholders.env}"
TPL="${OIDC_ROOT}/apiserver/clusterconfiguration-oidc.yaml.tpl"
OUT_DIR="${OIDC_ROOT}/apiserver/generated"
OUT="${OUT_DIR}/clusterconfiguration-oidc.yaml"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "note: ${ENV_FILE} missing — using placeholders.env.example" >&2
  ENV_FILE="${OIDC_ROOT}/placeholders.env.example"
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

need=(
  OIDC_ISSUER_URL OIDC_CLIENT_ID OIDC_USERNAME_CLAIM OIDC_GROUPS_CLAIM
  OIDC_USERNAME_PREFIX OIDC_GROUPS_PREFIX OIDC_CA_FILE
)
for v in "${need[@]}"; do
  [[ -n "${!v:-}" ]] || { echo "error: ${v} empty in ${ENV_FILE}" >&2; exit 1; }
done

mkdir -p "${OUT_DIR}"
BOOTSTRAP_CA="${OUT_DIR}/oidc-ca.crt"
if [[ ! -f "${BOOTSTRAP_CA}" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=oidc-placeholder-ca" \
    -keyout "${OUT_DIR}/oidc-ca.key" \
    -out "${BOOTSTRAP_CA}" 2>/dev/null
  echo "wrote bootstrap placeholder CA ${BOOTSTRAP_CA} (replace with IdP CA later)"
fi

export OIDC_ISSUER_URL OIDC_CLIENT_ID OIDC_USERNAME_CLAIM OIDC_GROUPS_CLAIM
export OIDC_USERNAME_PREFIX OIDC_GROUPS_PREFIX OIDC_CA_FILE
envsubst '${OIDC_ISSUER_URL} ${OIDC_CLIENT_ID} ${OIDC_USERNAME_CLAIM} ${OIDC_GROUPS_CLAIM} ${OIDC_USERNAME_PREFIX} ${OIDC_GROUPS_PREFIX} ${OIDC_CA_FILE}' \
  <"${TPL}" >"${OUT}"

echo "rendered ${OUT}"
