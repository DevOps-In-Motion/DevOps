# Ray Data + vLLM batch inference

Scaffold of the Databricks [Batch inference with Ray Data and vLLM](https://docs.databricks.com/aws/en/machine-learning/ai-runtime/cli/examples/ray-batch-inference) example, tuned for **small models first** so you can smoke-test locally before scaling to 7B / multi-GPU AIR nodes.

## Layout

```text
ray_batch_inference/
├── batch_inference.py   # Driver (ray.data.llm + vLLM)
├── train.yaml           # Optional Databricks AI Runtime workload
├── requirements.txt
├── scripts/run-local.sh # Local Ray head + driver
└── output/              # Local Parquet (gitignored)
```

## How it scales

| Setting | Local default | Scale-up example |
|---------|---------------|------------------|
| `MODEL_SOURCE` | `Qwen/Qwen2.5-0.5B-Instruct` | `Qwen/Qwen2.5-7B-Instruct` |
| `NUM_PROMPTS` | `16`–`32` | `1000+` |
| GPUs / `concurrency` | 1 replica | one replica per GPU (`total_gpus // tensor_parallel_size`) |
| `TENSOR_PARALLEL_SIZE` | `1` | `2+` for larger models |
| Output | `./output/batch_inference` | Unity Catalog volume (`OUTPUT_PATH` in `train.yaml`) |

Ray Data launches **one vLLM replica per GPU** (by default) and streams prompts through them via `build_processor` / `vLLMEngineProcessorConfig`.

## Prerequisites

- Linux + NVIDIA GPU (vLLM)
- Python 3.10+
- For Databricks AIR: [`air` CLI](https://docs.databricks.com/aws/en/machine-learning/ai-runtime/cli/examples/ray-batch-inference) authenticated + a writable UC volume

## Local quickstart

```bash
cd internal_dev_platforms/llm-platforms/vLLM/ray_batch_inference
python -m venv .venv && source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt

chmod +x scripts/run-local.sh
./scripts/run-local.sh
```

Or step by step:

```bash
ray start --head --num-gpus=1 --dashboard-host=127.0.0.1
export RAY_ADDRESS=auto
export MODEL_SOURCE=Qwen/Qwen2.5-0.5B-Instruct
export NUM_PROMPTS=16
export OUTPUT_PATH=./output/batch_inference
python batch_inference.py
ray stop
```

Inspect Parquet (example):

```bash
python -c "import ray; ray.init(); print(ray.data.read_parquet('output/batch_inference').take(2))"
```

### Useful env vars

| Variable | Meaning |
|----------|---------|
| `MODEL_SOURCE` | Hugging Face model id |
| `NUM_PROMPTS` | Rows from Alpaca (or built-in fallback) |
| `BATCH_SIZE` | Ray Data / vLLM batch size |
| `MAX_MODEL_LEN` | vLLM context length |
| `MAX_TOKENS` | Generation cap |
| `TENSOR_PARALLEL_SIZE` | GPUs per replica |
| `CONCURRENCY` | Override replica count (default: GPUs ÷ TP) |
| `OUTPUT_PATH` | Parquet directory |
| `RAY_ADDRESS` | Ray cluster address (`auto` if already started) |

## Databricks AIR

1. Set `OUTPUT_PATH` in `train.yaml` to your Unity Catalog volume.
2. Optionally bump `compute` / `MODEL_SOURCE` when leaving the 0.5B local path.
3. Submit:

```bash
air run -f train.yaml --dry-run
air run -f train.yaml --watch
```

## Next steps

- Multi-GPU local: `NUM_GPUS=2 ./scripts/run-local.sh` (or higher).
- Larger model: `MODEL_SOURCE=Qwen/Qwen2.5-7B-Instruct` + more VRAM / TP.
- Online serving: Ray Serve + vLLM (separate scaffold later).

## References

- [Databricks: Batch inference with Ray Data and vLLM](https://docs.databricks.com/aws/en/machine-learning/ai-runtime/cli/examples/ray-batch-inference)
- [Ray Data LLM API](https://docs.ray.io/en/latest/data/api/llm.html)
- [vLLM](https://docs.vllm.ai/)
