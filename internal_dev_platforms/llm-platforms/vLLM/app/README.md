# vLLM Distributed Inference App

This directory contains an application template for running highly scalable, GPU-accelerated large language model (LLM) inference using [vLLM](https://github.com/vllm-project/vllm) and [Ray](https://ray.io/) for distributed data processing.

## Features

- **Distributed Inference:** Efficiently batch and parallelize LLM inference workloads across multiple GPUs and nodes.
- **vLLM Integration:** Take advantage of vLLM's fast, memory-efficient inference engine.
- **Ray Data:** Use Ray Data and `map_batches` for distributed, high-throughput batch processing.
- **Customizable Sampling:** Easily adjust generation parameters (temperature, top-p, max tokens).
- **Automated Result Storage:** Save all inference outputs partitioned in Parquet format for easy downstream analytics.
- **Prometheus Exporting:** Ready for integration with OpenTelemetry and Prometheus for monitoring/exporting metrics.

## Directory Contents

- `cluster.py`: Sets up the distributed Ray inference workflow, manages batch processing with vLLM, and writes results to Parquet.
- `main.py`: Entrypoint that loads configuration and triggers distributed inference.
- `utils.py`: Utility functions for Ray cluster inspection/debugging.
- `requirements.txt`: All dependencies are pinned here, including vLLM, Ray, FlashAttention, Optree, and monitoring tools.

## Quickstart

1. **Install Requirements**

    ```
    pip install -r requirements.txt
    ```

2. **Set Environment Variables**

    Make sure to set:
    - `NUM_GPUS`: Number of GPUs to use (e.g., 4)
    - Other variables as appropriate (model name, prompt count, output path, etc.)

3. **Run the Distributed Inference Pipeline**

    ```
    python -m app.main
    ```

    This will:
    - Launch the Ray cluster workers (locally or remotely, as configured).
    - Run distributed text generation across your supplied prompts.
    - Save results to a Parquet file.

4. **Inspect the Output**

    After completion, a sample of generated outputs will be printed to the console, and all results are saved to the configured Parquet path.

## Customization

- **Change Prompts or Model:**
    - Edit the list of prompts and/or the `MODEL_NAME` in `cluster.py`.
- **Tweak Batch Size, Sampling, or Hardware:**
    - Adjust Ray Data's `batch_size`, the number of concurrent `LLMPredictor` instances, and other settings for your workload.

## Advanced

- This structure is suitable for running at small scale on a local machine, or at large scale as part of a managed compute environment.
- For debugging Ray resources, use the provided utility in `utils.py`.

## References

- [vLLM GitHub](https://github.com/vllm-project/vllm)
- [Ray Documentation](https://docs.ray.io/)
- [FlashAttention](https://github.com/Dao-AILab/flash-attention)

---