#!/usr/bin/env bash
# Admin applies: Namespace + OIDC group Roles/RoleBindings/ClusterRoleBindings.
# Developers never create namespaces — they only use RoleBinding rights in ${NAMESPACE}.
#
#   set -a; source k8s/oidc/placeholders.env; set +a
#   bash k8s/oidc/rbac/apply-rbac.sh

set -euo pipefail
OIDC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${OIDC_ENV_FILE:-${OIDC_ROOT}/placeholders.env}"
KUBECTL="${KUBECTL:-kubectl}"

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

need=(
  OIDC_GROUPS_PREFIX
  GROUP_PLATFORM_ADMIN GROUP_NAMESPACE_DEV GROUP_READONLY_VIEWER
  NAMESPACE
)
for v in "${need[@]}"; do
  [[ -n "${!v:-}" ]] || { echo "error: set ${v}" >&2; exit 1; }
done

render() {
  local src="$1"
  envsubst "$(printf '${%s} ' OIDC_GROUPS_PREFIX GROUP_PLATFORM_ADMIN GROUP_NAMESPACE_DEV GROUP_READONLY_VIEWER NAMESPACE)" \
    <"${src}"
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

while IFS= read -r -d '' f; do
  rel="${f#${OIDC_ROOT}/rbac/}"
  out="${TMP}/${rel}"
  mkdir -p "$(dirname "${out}")"
  render "${f}" >"${out}"
done < <(find "${OIDC_ROOT}/rbac" -type f -name '*.yaml' -print0)

echo "==> Applying admin OIDC RBAC (namespace=${NAMESPACE})"
"${KUBECTL}" apply -f "${TMP}/namespaces.yaml"
"${KUBECTL}" apply -f "${TMP}/platform-admin"
"${KUBECTL}" apply -f "${TMP}/namespace-dev"
"${KUBECTL}" apply -f "${TMP}/readonly-viewer"
echo "OK — groups in ${NAMESPACE}:"
echo "  admin:  ${OIDC_GROUPS_PREFIX}${GROUP_PLATFORM_ADMIN} (cluster)"
echo "  dev:    ${OIDC_GROUPS_PREFIX}${GROUP_NAMESPACE_DEV}"
echo "  viewer: ${OIDC_GROUPS_PREFIX}${GROUP_READONLY_VIEWER}"
