#!/usr/bin/env bash
# Run the DinD k3d container with inner Docker storage capped at 5GB.
# Linux only: uses a 5GB file-backed filesystem mounted at /var/lib/docker.
#
# Usage (from repo root):
#   ./k3d/run-dind-5g.sh
#
# First run creates a 5GB image file and mounts it; later runs reuse it.
# Requires: root or sudo for mount/umount (loop device). If mount fails, run:
#   sudo mount -o loop k3d/dind-5g-data/dind-5g.img k3d/dind-5g-data/mount
# then run this script again.
#
# Optional env:
#   DIND_5G_DIR=/path/to/dir   where to put the 5GB image and mount (default: ./k3d/dind-5g-data)
#   DIND_5G_SIZE_MB=5120       size in MB (default 5120 = 5GB)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIND_5G_DIR="${DIND_5G_DIR:-$REPO_ROOT/k3d/dind-5g-data}"
DIND_5G_SIZE_MB="${DIND_5G_SIZE_MB:-5120}"
IMG_FILE="$DIND_5G_DIR/dind-5g.img"
MOUNT_POINT="$DIND_5G_DIR/mount"

echo "=== DinD with 5GB disk cap (data dir: $DIND_5G_DIR) ==="

case "$(uname -s)" in
  Linux)
    ;;
  *)
    echo "This script is for Linux only. Docker has no per-container disk limit on Mac/Windows."
    echo "On Mac: Docker Desktop → Settings → Resources → Disk image size (reduce to limit overall usage)."
    exit 1
    ;;
esac

mkdir -p "$DIND_5G_DIR" "$MOUNT_POINT"

if [[ ! -f "$IMG_FILE" ]]; then
  echo "Creating ${DIND_5G_SIZE_MB}MB image file (one-time)..."
  dd if=/dev/zero of="$IMG_FILE" bs=1M count="$DIND_5G_SIZE_MB" status=progress
  mkfs.ext4 -q -F "$IMG_FILE"
  echo "Created $IMG_FILE"
fi

if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
  echo "Mounting 5GB filesystem at $MOUNT_POINT..."
  if mount -o loop "$IMG_FILE" "$MOUNT_POINT" 2>/dev/null; then
    echo "Mounted."
  else
    echo "Mount failed. Try: sudo mount -o loop $IMG_FILE $MOUNT_POINT"
    echo "Then run this script again, or run the container manually:"
    echo "  docker run --rm -it --privileged --cgroupns=host -p 8080:8080 -p 8443:8443 -v wiki-data:/data -v $MOUNT_POINT:/var/lib/docker wiki-k3d-dind"
    exit 1
  fi
fi

echo "Starting DinD with -v $MOUNT_POINT:/var/lib/docker (5GB cap)..."
cd "$REPO_ROOT"
docker rm -f wiki-k3d-dind 2>/dev/null || true
docker run --rm -it --name wiki-k3d-dind --privileged --cgroupns=host \
  -p 8080:8080 -p 8443:8443 \
  -v wiki-data:/data \
  -v "$MOUNT_POINT:/var/lib/docker" \
  wiki-k3d-dind

echo "To unmount the 5GB filesystem after the container exits:"
echo "  sudo umount $MOUNT_POINT"
