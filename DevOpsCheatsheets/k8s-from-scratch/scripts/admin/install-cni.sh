#!/usr/bin/env bash
set -euo pipefail

# Install Calico operator (Installation CR applied separately via Make).

kubectl apply --server-side -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/operator-crds.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/tigera-operator.yaml
