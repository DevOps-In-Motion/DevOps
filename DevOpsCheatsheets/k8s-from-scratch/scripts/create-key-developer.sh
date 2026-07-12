#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

openssl genrsa -out "${SCRIPT_DIR}/nginx-deployer.key" 2048

openssl req -new -key "${SCRIPT_DIR}/nginx-deployer.key" \
  -out "${SCRIPT_DIR}/nginx-deployer.csr" \
  -subj "/CN=nginx-deployer/O=nginx-deployers"
