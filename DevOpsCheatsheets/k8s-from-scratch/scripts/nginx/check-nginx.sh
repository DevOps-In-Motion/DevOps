#!/usr/bin/env bash
set -euo pipefail

# Check: client → Gateway → HTTPRoute → Service → Pods (+ static assets)

NS="${NS:-nginx-app}"
KCFG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nginx-deployer.kubeconfig"
if [[ -s "${KCFG}" ]]; then K=(kubectl --kubeconfig="${KCFG}"); else K=(kubectl); fi

"${K[@]}" get gatewayclass
"${K[@]}" -n "${NS}" get gateway,httproute,svc,pods -o wide
echo

ADDR="$("${K[@]}" -n "${NS}" get gateway nginx -o jsonpath='{.status.addresses[0].value}')"
[[ -n "${ADDR}" ]] || { echo "error: Gateway has no address" >&2; exit 1; }
URL="https://${ADDR}/"

"${K[@]}" -n "${NS}" wait --for=condition=Ready certificate/nginx-tls --timeout=60s 2>/dev/null || true
code="$(curl -sk --connect-timeout 10 -o /tmp/gw-body -w '%{http_code}' "${URL}")"
echo "Gateway ${URL} → HTTP ${code}"
grep -i '<title>' /tmp/gw-body || true
[[ "${code}" == "200" ]] || exit 1

grep -q 'stars.gif' /tmp/gw-body || { echo "error: page missing stars.gif background" >&2; exit 1; }
grep -q 'pirate.gif' /tmp/gw-body || { echo "error: page missing pirate.gif" >&2; exit 1; }

for asset in stars.gif pirate.gif; do
  ac="$(curl -sk --connect-timeout 10 -o /dev/null -w '%{http_code}' "${URL}${asset}")"
  echo "  ${asset} → HTTP ${ac}"
  [[ "${ac}" == "200" ]] || exit 1
done

echo "OK — make browse"
