#!/usr/bin/env bash
# Skeleton validator — cert-admin kubeconfig. No production IdP required.
#   bash k8s/oidc/docs/validate.sh

set -euo pipefail
OIDC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${OIDC_ROOT}/../.." && pwd)"
ENV_FILE="${OIDC_ENV_FILE:-${OIDC_ROOT}/placeholders.env}"
[[ -f "${ENV_FILE}" ]] || ENV_FILE="${OIDC_ROOT}/placeholders.env.example"
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

K=(kubectl)
fail=0

echo "==> A. apiserver OIDC flags (via controlplane SSH if available)"
if command -v vagrant >/dev/null && [[ -d "${REPO_ROOT}/.vagrant" ]]; then
  if cd "${REPO_ROOT}" && vagrant ssh controlplane -c \
    "sudo grep -q oidc-issuer-url /etc/kubernetes/manifests/kube-apiserver.yaml && sudo grep -q oidc-groups-prefix /etc/kubernetes/manifests/kube-apiserver.yaml"; then
    echo "OK: oidc flags present in static Pod manifest (kubeadm-managed)"
  else
    echo "FAIL: oidc flags missing on controlplane"; fail=1
  fi
else
  echo "SKIP: vagrant/controlplane not available"
fi

echo "==> B. RBAC objects"
if "${K[@]}" get clusterrolebinding oidc-platform-admin >/dev/null 2>&1; then
  echo "OK: oidc-platform-admin ClusterRoleBinding exists"
  "${K[@]}" auth can-i '*' '*' --as=t --as-group="${OIDC_GROUPS_PREFIX}${GROUP_PLATFORM_ADMIN}" >/dev/null \
    && echo "OK: platform-admin can-i *" \
    || { echo "FAIL: platform-admin can-i"; fail=1; }
else
  echo "SKIP: RBAC not applied yet (bash k8s/oidc/rbac/apply-rbac.sh)"
fi

echo "==> C. Gatekeeper constraints"
if "${K[@]}" get constrainttemplate k8sdenywildcardnamespaceroles >/dev/null 2>&1; then
  echo "OK: ConstraintTemplates present"
else
  echo "SKIP: Gatekeeper templates not applied"
fi

echo "==> Done (fail=${fail})"
exit "${fail}"
