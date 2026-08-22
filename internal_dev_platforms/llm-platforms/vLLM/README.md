# vLLM (legacy location)

The **Ray Data + vLLM** batch scaffold moved to:

**[`agent-solutions/LLM-hosting/ray_batch_inference/`](../../../agent-solutions/LLM-hosting/ray_batch_inference/)**

```bash
cd ../../../agent-solutions/LLM-hosting/ray_batch_inference
pip install -r requirements.txt
./scripts/run-local.sh
```

Remaining here (`app/`, `terraform/`, `scripts/`, `webhook/`) is older AWS / Ollama-oriented infra, not the Ray batch path.
