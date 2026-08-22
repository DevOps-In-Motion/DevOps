# LLM hosting

Agent-oriented solutions for hosting and scaling LLMs.

## Projects

| Path | Description |
|------|-------------|
| [`ray_batch_inference/`](ray_batch_inference/) | Offline batch inference with **Ray Data + vLLM** (small-model local defaults; Databricks AIR `train.yaml` for scale). |

```bash
cd ray_batch_inference
pip install -r requirements.txt
./scripts/run-local.sh
```

See [`ray_batch_inference/README.md`](ray_batch_inference/README.md).
