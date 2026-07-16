#!/usr/bin/env bash
set -euo pipefail

# nginx-deployer ONLY: apply app in nginx-app (never admin).
#   bash /vagrant/scripts/nginx/apply-app.sh
#   make app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KCFG="${SCRIPT_DIR}/nginx-deployer.kubeconfig"
K=(kubectl --kubeconfig="${KCFG}")

[[ -s "${KCFG}" ]] || {
  echo "error: missing ${KCFG}" >&2
  echo "Admin must finish: make admin  (issues nginx-deployer cert + kubeconfig)" >&2
  exit 1
}

ctx="$("${K[@]}" config current-context)"
user="$("${K[@]}" config view --minify -o jsonpath='{.users[0].name}')"
echo "==> Applying as context=${ctx} user=${user}"

if [[ "${user}" != "nginx-deployer" ]]; then
  echo "error: refused — app must be applied as nginx-deployer, got user=${user}" >&2
  exit 1
fi

who="$("${K[@]}" auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null || true)"
if [[ -n "${who}" && "${who}" != "nginx-deployer" ]]; then
  echo "error: API sees user=${who}, expected nginx-deployer" >&2
  exit 1
fi
[[ -n "${who}" ]] && echo "==> API identity: ${who}"

"${K[@]}" auth can-i create deployments -n nginx-app >/dev/null
if "${K[@]}" auth can-i create nodes >/dev/null 2>&1; then
  echo "warn: deployer can create nodes (RBAC wider than expected)" >&2
fi

if ! "${K[@]}" get gatewayclass nginx >/dev/null 2>&1; then
  echo "error: GatewayClass nginx missing — finish make admin (gateway-api) first" >&2
  exit 1
fi

echo "==> Static site ConfigMap (index.html + stars.gif + pirate.gif)"
STATIC="${ROOT}/k8s/nginx/static"
[[ -f "${STATIC}/index.html" && -f "${STATIC}/stars.gif" && -f "${STATIC}/pirate.gif" ]] || {
  echo "error: missing ${STATIC}/index.html, stars.gif, or pirate.gif" >&2
  echo "Regenerate stars: bash scripts/nginx/generate-stars.sh" >&2
  exit 1
}
"${K[@]}" -n nginx-app create configmap nginx-html \
  --from-file="${STATIC}/index.html" \
  --from-file="${STATIC}/stars.gif" \
  --from-file="${STATIC}/pirate.gif" \
  --dry-run=client -o yaml | "${K[@]}" apply -f -

echo "==> Deployment + Service (nginx-deployer)"
"${K[@]}" apply -f "${ROOT}/k8s/nginx/nginx-webserver.yaml"
# Ensure pods remount ConfigMap after content changes.
"${K[@]}" -n nginx-app rollout restart deploy/nginx
"${K[@]}" -n nginx-app rollout status deploy/nginx --timeout=180s

echo "==> Certificate + Gateway + HTTPRoute (nginx-deployer)"
"${K[@]}" apply -f "${ROOT}/k8s/nginx/nginx-routes.yaml"
"${K[@]}" -n nginx-app wait --for=condition=Ready certificate/nginx-tls --timeout=180s

# Wait for NGF dataplane Service + MetalLB VIP (LoadBalancer — not NodePort / port-forward).
for _ in $(seq 1 90); do
  vip="$("${K[@]}" -n nginx-app get svc nginx-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "${vip}" ]]; then
    echo "Gateway LoadBalancer VIP: ${vip}"
    break
  fi
  sleep 2
done

"${K[@]}" -n nginx-app wait --for=condition=Programmed gateway/nginx --timeout=120s || true
"${K[@]}" -n nginx-app get deploy,svc,certificate,gateway,httproute

echo
echo "App applied as nginx-deployer."
echo "Browse: make browse"
echo "Check:  make check-nginx"
