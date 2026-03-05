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

# Check disk space before any pulls (avoid 'no space left on device' with a clear message)
AVAIL=$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -n "$AVAIL" && "$AVAIL" -lt 5120 ]]; then
  echo "ERROR: Low disk space (${AVAIL}MB free). DinD needs ~5GB+ for images."
  echo "  On the HOST run: ./k3d/cleanup.sh  ;  docker system prune -af  ;  docker volume prune -f"
  echo "  Then ensure the host has 10GB+ free (df -h) and run again."
  echo "  Or use host socket: docker run -v /var/run/docker.sock:/var/run/docker.sock -p 8080:8080 -p 8443:8443 wiki-k3d"
  exit 1
fi

# Verify Docker can create containers (catches broken DinD early)
echo "Verifying Docker can create containers..."
if ! docker run --rm alpine true 2>/dev/null; then
  echo "ERROR: Docker cannot run containers. DinD may be broken (e.g. cgroups) or out of disk (no space left on device)."
  echo "  If you saw 'no space left on device' above: on the HOST run: ./k3d/cleanup.sh  ;  docker system prune -af  ;  docker volume prune -f  ;  then retry."
  echo "  Otherwise ensure --privileged and no Docker socket."
  exit 1
fi
echo "Docker OK. Creating k3d cluster..."

# Run the k3d + Helm entrypoint
/app/k3d/entrypoint.sh || exit $?

# DinD only: keep container alive while inner Docker (and thus the cluster) is running.
# When dockerd exits, we exit and the container stops.
echo "Cluster ready. Container stays up while cluster runs (Ctrl+C to stop)."
wait $DOCKERD_PID
