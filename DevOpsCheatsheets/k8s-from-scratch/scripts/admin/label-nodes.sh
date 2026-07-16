#!/usr/bin/env bash
set -euo pipefail

kubectl label node worker1 node-role.kubernetes.io/worker=worker --overwrite
kubectl label node worker2 node-role.kubernetes.io/worker=worker --overwrite
