#!/usr/bin/env bash
set -euo pipefail

# Optional shareable HTTPS URL via ngrok (Mac host).
# Upstream: localhost:8443 → Vagrant SSH -L → Gateway → HTTPRoute → Service → Pods
#
#   make share
#   Prerequisites: ngrok installed + authed (`ngrok config add-authtoken …`)
#                  app deployed; browse tunnel starts automatically if needed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${SHARE_PORT:-8443}"
LOCAL="https://127.0.0.1:${PORT}/"
PIDFILE="${ROOT}/scripts/nginx/.ngrok.pid"
LOGFILE="${ROOT}/scripts/nginx/.ngrok.log"
URLFILE="${ROOT}/scripts/nginx/.ngrok-url"
API="${NGROK_API:-http://127.0.0.1:4040}"

cd "${ROOT}"

need_ngrok() {
  if ! command -v ngrok >/dev/null 2>&1; then
    echo "error: ngrok not found on PATH" >&2
    echo "  Install: https://ngrok.com/download  (or: brew install ngrok/ngrok/ngrok)" >&2
    echo "  Then:    ngrok config add-authtoken <token>" >&2
    exit 1
  fi
}

ensure_local() {
  local code
  code="$(curl -sk --connect-timeout 2 -o /dev/null -w '%{http_code}' "${LOCAL}" 2>/dev/null || true)"
  if [[ "${code}" == "200" ]]; then
    echo "==> Local tunnel already up (${LOCAL})"
    return 0
  fi
  echo "==> Starting local forward (make browse)"
  OPEN_BROWSER=0 bash "${ROOT}/scripts/nginx/browse.sh"
  code="$(curl -sk --connect-timeout 5 -o /dev/null -w '%{http_code}' "${LOCAL}" || true)"
  [[ "${code}" == "200" ]] || {
    echo "error: ${LOCAL} not reachable (HTTP ${code}) — run make app && make browse first" >&2
    exit 1
  }
}

stop_ngrok() {
  if [[ -f "${PIDFILE}" ]]; then
    kill "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null || true
    rm -f "${PIDFILE}"
  fi
  # Stale agent still holding the local API
  if command -v lsof >/dev/null; then
    local p
    p="$(lsof -nP -iTCP:4040 -sTCP:LISTEN -t 2>/dev/null || true)"
    [[ -n "${p}" ]] && kill ${p} 2>/dev/null || true
  fi
  pkill -f "ngrok http .*${PORT}" 2>/dev/null || true
  rm -f "${URLFILE}"
  sleep 0.3
}

wait_public_url() {
  local i url
  for i in $(seq 1 40); do
    url="$(curl -sf "${API}/api/tunnels" 2>/dev/null \
      | python3 -c 'import json,sys
d=json.load(sys.stdin)
for t in d.get("tunnels",[]):
  u=t.get("public_url","")
  if u.startswith("https://"):
    print(u); break' 2>/dev/null || true)"
    if [[ -n "${url}" ]]; then
      echo "${url}"
      return 0
    fi
    sleep 0.25
  done
  return 1
}

need_ngrok
ensure_local
stop_ngrok

echo "==> ngrok http ${LOCAL}"
: >"${LOGFILE}"
# Forward to the lab HTTPS Gateway tunnel. ngrok terminates public TLS;
# upstream is the self-signed lab cert (agent skips verify by default).
ngrok http "${LOCAL}" --log=stdout --log-format=logfmt \
  >"${LOGFILE}" 2>&1 &
echo $! >"${PIDFILE}"

pub="$(wait_public_url)" || {
  echo "error: ngrok did not publish a URL" >&2
  echo "---- ${LOGFILE} (tail) ----" >&2
  tail -n 40 "${LOGFILE}" >&2 || true
  echo >&2
  echo "If you see auth errors: ngrok config add-authtoken <token>" >&2
  stop_ngrok
  exit 1
}

echo "${pub}" >"${URLFILE}"
echo
echo "Shareable URL:  ${pub}/"
echo "Local upstream: ${LOCAL}"
echo "ngrok UI:       ${API}"
echo "ngrok PID:      $(cat "${PIDFILE}")  (leave running while sharing)"
echo
echo "Stop:  kill \$(cat scripts/nginx/.ngrok.pid)"
