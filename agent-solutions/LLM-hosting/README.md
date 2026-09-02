# LLM hosting

Agent-oriented solutions for hosting and scaling LLMs.

## Projects

| Path | Description |
|------|-------------|
| [`ray_batch_inference/`](ray_batch_inference/) | Ray Data batch + Ray Serve online paths for **vLLM**, with prefill/decode metrics, Automatic Prefix Caching, and continuous-batching-aware replica design ([`architecture.md`](ray_batch_inference/architecture.md), [`GAPS.md`](ray_batch_inference/GAPS.md)). |

```bash
cd ray_batch_inference
pip install -r requirements.txt
./scripts/run-local.sh
```

See [`ray_batch_inference/README.md`](ray_batch_inference/README.md).
