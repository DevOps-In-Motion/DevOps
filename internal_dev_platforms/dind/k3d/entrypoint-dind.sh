#!/usr/bin/env bash
# Run with --privileged. Do NOT mount the Docker socket.
#   docker run --rm -it --privileged --cgroupns=host -p 8080:8080 -p 8443:8443 -v wiki-data:/data wiki-k3d-dind

set -e

echo "=== Starting Docker daemon (DinD, --privileged, no socket) ==="
# vfs storage driver is more reliable when Docker runs inside Docker (nested); overlay can fail.
dockerd --storage-driver vfs &
DOCKERD_PID=$!

# Wait for Docker socket and daemon to be ready
for i in $(seq 1 60); do
  if docker info &>/dev/null; then
    echo "Docker daemon is ready."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Docker daemon did not become ready in time."
    echo "  Run with: --privileged --cgroupns=host. Do not mount the Docker socket."
    kill $DOCKERD_PID 2>/dev/null || true
    exit 1
  fi
  sleep 1
done

# Verify Docker can create containers (catches broken DinD early)
echo "Verifying Docker can create containers..."
if ! docker run --rm alpine true 2>/dev/null; then
  echo "ERROR: Docker cannot run containers. DinD may be broken (e.g. cgroups). Ensure --privileged and no Docker socket."
  exit 1
fi
echo "Docker OK. Creating k3d cluster..."

# Run the k3d + Helm entrypoint
/app/k3d/entrypoint.sh || exit $?

# DinD only: keep container alive while inner Docker (and thus the cluster) is running.
# When dockerd exits, we exit and the container stops.
echo "Cluster ready. Container stays up while cluster runs (Ctrl+C to stop)."
wait $DOCKERD_PID
