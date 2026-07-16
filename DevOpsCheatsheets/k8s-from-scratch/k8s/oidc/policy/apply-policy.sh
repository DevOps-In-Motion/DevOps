#!/usr/bin/env bash
# Apply Gatekeeper templates then constraints (Gatekeeper must already be installed).
#   set -a; source k8s/oidc/placeholders.env; set +a
#   bash k8s/oidc/policy/apply-policy.sh

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

: "${OIDC_GROUPS_PREFIX:?}"
: "${GROUP_PLATFORM_ADMIN:?}"

if ! "${KUBECTL}" get crd constrainttemplates.templates.gatekeeper.sh >/dev/null 2>&1; then
  echo "error: Gatekeeper CRDs not found — install Gatekeeper first, then re-run" >&2
  exit 1
fi

echo "==> ConstraintTemplates"
"${KUBECTL}" apply -f "${OIDC_ROOT}/policy/templates/"
echo "==> waiting for constraint CRDs"
for kind in \
  k8sblockclusterrolebindingunlessplatformadmin \
  k8sdenywildcardnamespaceroles \
  k8senforcenamespacerolebindingisolation
do
  "${KUBECTL}" wait --for=condition=Established "crd/${kind}.constraints.gatekeeper.sh" --timeout=120s
done

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
for f in "${OIDC_ROOT}/policy/constraints/"*.yaml; do
  base="$(basename "${f}")"
  envsubst '${OIDC_GROUPS_PREFIX} ${GROUP_PLATFORM_ADMIN}' <"${f}" >"${TMP}/${base}"
done

echo "==> Constraints"
"${KUBECTL}" apply -f "${TMP}/"
echo "Gatekeeper OIDC policies applied."
