#!/usr/bin/env bash
set -euo pipefail

# https://localhost:8443/ via Vagrant SSH local forward → Gateway
#   client → Gateway → HTTPRoute → Service → Pods

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIDFILE="${ROOT}/scripts/nginx/.browse-ssh.pid"
SSHCFG="${ROOT}/scripts/nginx/.vagrant-worker1-ssh"
URL="https://localhost:8443/"
PORT=8443

cd "${ROOT}"

stop_tunnel() {
  if [[ -f "${PIDFILE}" ]]; then
    kill "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null || true
    rm -f "${PIDFILE}"
  fi
  # Anything still bound to the local port
  if command -v lsof >/dev/null; then
    local p
    p="$(lsof -nP -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null || true)"
    [[ -n "${p}" ]] && kill ${p} 2>/dev/null || true
  fi
  sleep 0.3
}

ADDR="$(vagrant ssh controlplane -c \
  "kubectl -n nginx-app get gateway nginx -o jsonpath='{.status.addresses[0].value}'" 2>/dev/null | tr -d '\r')"
[[ -n "${ADDR}" ]] || { echo "error: Gateway has no address" >&2; exit 1; }

echo "==> Gateway ${ADDR}"
gw="$(curl -sk --connect-timeout 8 -o /dev/null -w '%{http_code}' "https://${ADDR}/" || true)"
[[ "${gw}" == "200" ]] || { echo "error: Gateway HTTP ${gw}" >&2; exit 1; }

stop_tunnel

vagrant ssh-config worker1 >"${SSHCFG}"
echo "==> ssh -L ${PORT}:${ADDR}:443 (worker1)"
ssh -F "${SSHCFG}" -o ExitOnForwardFailure=yes -N \
  -L "127.0.0.1:${PORT}:${ADDR}:443" worker1 >/dev/null 2>&1 &
echo $! >"${PIDFILE}"

# Wait until localhost accepts connections
ok=0
for _ in $(seq 1 20); do
  if curl -sk --connect-timeout 1 -o /dev/null "https://127.0.0.1:${PORT}/" 2>/dev/null; then
    ok=1
    break
  fi
  sleep 0.25
done

code="$(curl -sk --connect-timeout 5 -o /tmp/loc-body -w '%{http_code}' "${URL}" || true)"
echo "==> ${URL}  (HTTP ${code})"
if [[ "${ok}" != "1" || "${code}" != "200" ]]; then
  echo "error: SSH tunnel failed (is port ${PORT} free?)" >&2
  stop_tunnel
  exit 1
fi
grep -i '<title>' /tmp/loc-body || true
echo
echo "Tunnel PID $(cat "${PIDFILE}") — leave it running while you browse."
if [[ "${OPEN_BROWSER:-1}" != "0" ]] && command -v open >/dev/null; then
  open "${URL}"
fi
