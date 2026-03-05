#!/usr/bin/env bash
# Run wiki stack with privileged DinD (no Docker socket). From repo root: ./testing/test-k3d.sh
# Then: http://localhost:8080/users  http://localhost:8080/posts  http://localhost:8080/grafana  (admin/admin)

set -e
cd "$(dirname "$0")/.."

echo "=== Building DinD image (run with --privileged, no socket) ==="
docker build -f Dockerfile.dind -t wiki-k3d-dind .

echo ""
# Free ports 8080 and 8443: remove named container if present, then any other container using those ports
docker rm -f wiki-k3d-dind 2>/dev/null || true
for id in $(docker ps -aq 2>/dev/null); do
  if docker port "$id" 2>/dev/null | grep -qE ':(8080|8443)(/|$)'; then
    echo "=== Removing container $id (frees 8080 or 8443) ==="
    docker rm -f "$id" 2>/dev/null || true
  fi
done
echo "=== Running with --privileged. Ports 8080, 8443. Ctrl+C to stop. ==="
# Required: --privileged. Do not mount the Docker socket.
# Optional: -v wiki-data:/data  to persist Postgres across container restarts (Option 1).
# --cgroupns=host helps DinD; if it still fails, fallback: docker run -v /var/run/docker.sock:/var/run/docker.sock wiki-k3d
# docker run --rm -it --privileged --userns=host --cgroupns=host -p 8080:8080 -p 8443:8443 -v wiki-data:/data wiki-k3d-dind
docker run -d --name wiki-k3d-dind --userns=host --privileged --cgroupns=host -p 8080:8080 -p 8443:8443 -v wiki-data:/data wiki-k3d-dind