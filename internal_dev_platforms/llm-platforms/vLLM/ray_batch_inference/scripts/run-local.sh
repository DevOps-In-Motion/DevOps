#!/usr/bin/env bash
# Local smoke test: Ray head + small-model batch inference.
# Requires: NVIDIA GPU, CUDA-capable vLLM install, Python 3.10+.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export MODEL_SOURCE="${MODEL_SOURCE:-Qwen/Qwen2.5-0.5B-Instruct}"
export NUM_PROMPTS="${NUM_PROMPTS:-16}"
export BATCH_SIZE="${BATCH_SIZE:-4}"
export MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"
export MAX_TOKENS="${MAX_TOKENS:-64}"
export TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-1}"
export OUTPUT_PATH="${OUTPUT_PATH:-$ROOT/output/batch_inference}"
export RAY_TEMP_DIR="${RAY_TEMP_DIR:-/tmp/ray}"

NUM_GPUS="${NUM_GPUS:-1}"
RAY_PORT="${RAY_PORT:-6379}"
STARTED_RAY=0

cleanup() {
  if [[ "$STARTED_RAY" -eq 1 ]]; then
    echo "Stopping Ray…"
    ray stop --force >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! ray status >/dev/null 2>&1; then
  echo "Starting Ray head with ${NUM_GPUS} GPU(s)…"
  ray start --head --port="$RAY_PORT" --num-gpus="$NUM_GPUS" --dashboard-host=127.0.0.1
  STARTED_RAY=1
else
  echo "Using existing Ray cluster."
fi

export RAY_ADDRESS="${RAY_ADDRESS:-auto}"
python batch_inference.py
