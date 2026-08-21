# vLLM platforms

## Active scaffold

**[ray_batch_inference/](ray_batch_inference/)** — offline batch inference with **Ray Data + vLLM**, based on the Databricks [AI Runtime example](https://docs.databricks.com/aws/en/machine-learning/ai-runtime/cli/examples/ray-batch-inference). Defaults to a small public model (`Qwen/Qwen2.5-0.5B-Instruct`) for local GPU testing; `train.yaml` is ready for AIR when you scale up.

```bash
cd ray_batch_inference
pip install -r requirements.txt
./scripts/run-local.sh
```

## Legacy

- `app/` — old Databricks serverless / custom `LLMPredictor` stub (deprecated; redirects to `ray_batch_inference/`).
- `terraform/`, `scripts/`, `webhook/` — earlier AWS free-tier / Ollama-oriented infra (separate from the Ray batch path).

## Scale path

1. Local 1×GPU, 0.5B model  
2. More GPUs / larger model via env (`MODEL_SOURCE`, `NUM_GPUS`, `TENSOR_PARALLEL_SIZE`)  
3. Databricks AIR (`air run -f train.yaml`) with a Unity Catalog `OUTPUT_PATH`
