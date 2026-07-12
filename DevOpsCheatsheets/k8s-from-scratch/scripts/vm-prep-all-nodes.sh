#!/bin/bash
set -euo pipefail

for node in worker1 worker2; do
  echo "Provisioning $node..."
  vagrant ssh "$node" -c "sudo bash -s" < vm-node-setup.sh
done