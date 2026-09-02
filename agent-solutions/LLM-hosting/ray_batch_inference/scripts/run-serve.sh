#!/usr/bin/env bash
# Start Ray Serve + AsyncLLMEngine (streaming, continuous batching per replica).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export MODEL_SOURCE="${MODEL_SOURCE:-Qwen/Qwen2.5-0.5B-Instruct}"
export MAX_ONGOING_REQUESTS="${MAX_ONGOING_REQUESTS:-64}"
export NUM_REPLICAS="${NUM_REPLICAS:-1}"
export SERVE_NUM_GPUS="${SERVE_NUM_GPUS:-1}"

if ! ray status >/dev/null 2>&1; then
  echo "Starting Ray head…"
  ray start --head --num-gpus="${SERVE_NUM_GPUS}" --dashboard-host=127.0.0.1
fi

echo "Deploying serving.app (NUM_REPLICAS=${NUM_REPLICAS})…"
# Block in foreground; Ctrl-C to stop.
serve run serving.app:app --address=auto
