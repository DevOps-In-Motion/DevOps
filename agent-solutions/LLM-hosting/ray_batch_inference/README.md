# Ray Data + vLLM (batch) and Ray Serve (online)

Scaffold of the Databricks [Batch inference with Ray Data and vLLM](https://docs.databricks.com/aws/en/machine-learning/ai-runtime/cli/examples/ray-batch-inference) example, plus an architecture pass for:

1. **Prefill → decode** awareness (TTFT / ITL on the Serve path)
2. **Automatic Prefix Caching** + APC-friendly prompt ordering
3. **Continuous batching** inside one `AsyncLLMEngine` per replica (Ray routes; engine schedules)

See **[`architecture.md`](architecture.md)** for the full design notes and deliverables.
See **[`GAPS.md`](GAPS.md)** for production gaps and ordered next steps (self-hosted only, customer load).

## Layout

```text
ray_batch_inference/
├── architecture.md          # Prefill/decode, APC, continuous batching
├── GAPS.md                  # Gaps + next steps (capacity, platform, ops)
├── model_config.yaml        # Model + tokenizer + chat_template_version + engine flags
├── config.py / prompts.py / metrics.py
├── batch_inference.py       # Offline Ray Data + vLLM (APC enabled)
├── serving/app.py           # Online Ray Serve + AsyncLLMEngine (streaming)
├── train.yaml               # Optional Databricks AIR workload
├── scripts/run-local.sh     # Batch local
├── scripts/run-serve.sh     # Serve local
├── scripts/bench_prefix_cache.py
└── output/                  # Local Parquet (gitignored)
```

## Local batch

```bash
cd agent-solutions/LLM-hosting/ray_batch_inference
pip install -r requirements.txt
./scripts/run-local.sh
```

## Local Serve (streaming + TTFT/ITL)

```bash
./scripts/run-serve.sh
# Then POST JSON {"prompt":"What is continuous batching?"} to the Serve HTTP endpoint.
```

## Prefix-cache bench

```bash
python scripts/bench_prefix_cache.py
```

## Key env vars

| Variable | Meaning |
|----------|---------|
| `MODEL_SOURCE` | HF model id (pinned with `chat_template_version` in `model_config.yaml`) |
| `ENABLE_PREFIX_CACHING` | APC (default true) |
| `ENABLE_CHUNKED_PREFILL` | Chunked prefill (default true) |
| `MAX_ONGOING_REQUESTS` | Serve concurrency into one engine (default 64 — do not set to 1) |
| `NUM_REPLICAS` | Serve replicas (routing is not cache-locality-aware yet) |
| `MULTI_TENANT` + `CACHE_SALT_HMAC_SECRET` | Server-side prefix namespace |

## References

- [Databricks Ray Data + vLLM](https://docs.databricks.com/aws/en/machine-learning/ai-runtime/cli/examples/ray-batch-inference)
- [vLLM Automatic Prefix Caching](https://docs.vllm.ai/en/latest/features/automatic_prefix_caching.html)
- [Ray Serve](https://docs.ray.io/en/latest/serve/index.html)
