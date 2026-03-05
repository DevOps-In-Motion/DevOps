from serverless_gpu.ray import ray_launch
import os

# Set Ray temp directory
os.environ['RAY_TEMP_DIR'] = '/tmp/ray'

@ray_launch(gpus=NUM_GPUS, gpu_type='a10', remote=True)
def run_distributed_inference():
    """Run distributed LLM inference using Ray Data and vLLM with map_batches."""
    from typing import Dict, List
    from datetime import datetime
    import numpy as np
    import ray
    from vllm import LLM, SamplingParams

    # Sample prompts for inference
    base_prompts = [
        "Hello, my name is",
        "The president of the United States is",
        "The future of AI is",
    ]

    # Scale up prompts for distributed processing
    prompts = base_prompts * (NUM_PROMPTS // len(base_prompts))
    ds = ray.data.from_items(prompts)

    print(f"✓ Created Ray dataset with {ds.count()} prompts")

    # Sampling parameters for text generation
    sampling_params = SamplingParams(
        temperature=0.8,
        top_p=0.95,
        max_tokens=100
    )

    class LLMPredictor:
        """vLLM-based predictor for batch inference."""

        def __init__(self):
            self.llm = LLM(
                model=MODEL_NAME,
                tensor_parallel_size=1,
                dtype="bfloat16",
                trust_remote_code=True,
                gpu_memory_utilization=0.90,
                max_model_len=8192,
                enable_prefix_caching=True,
                enable_chunked_prefill=True,
                max_num_batched_tokens=8192,
            )
            self.model_name = MODEL_NAME
            print(f"✓ vLLM engine initialized with model: {MODEL_NAME}")

        def __call__(self, batch: Dict[str, np.ndarray]) -> Dict[str, list]:
            """Process a batch of prompts."""
            outputs = self.llm.generate(batch["item"], sampling_params)

            prompt_list: List[str] = []
            generated_text_list: List[str] = []
            model_list: List[str] = []
            timestamp_list: List[str] = []

            for output in outputs:
                prompt_list.append(output.prompt)
                generated_text_list.append(
                    ' '.join([o.text for o in output.outputs])
                )
                model_list.append(self.model_name)
                timestamp_list.append(datetime.now().isoformat())

            return {
                "prompt": prompt_list,
                "generated_text": generated_text_list,
                "model": model_list,
                "timestamp": timestamp_list,
            }

    # Configure number of parallel vLLM instances
    num_instances = NUM_GPUS

    # Apply the predictor across the dataset using map_batches
    ds = ds.map_batches(
        LLMPredictor,
        concurrency=num_instances,
        batch_size=32,
        num_gpus=1,
        num_cpus=12
    )

    # =========================================================================
    # Write results to Parquet (stored in Unity Catalog Volume)
    # =========================================================================
    print(f"\n📦 Writing results to Parquet: {PARQUET_OUTPUT_PATH}")
    ds.write_parquet(PARQUET_OUTPUT_PATH, mode="overwrite")
    print(f"✓ Parquet files written successfully")

    # Collect sample outputs for display
    sample_outputs = ray.data.read_parquet(PARQUET_OUTPUT_PATH).take(limit=10)

    print("\n" + "="*60)
    print("SAMPLE INFERENCE RESULTS")
    print("="*60 + "\n")

    for i, output in enumerate(sample_outputs):
        prompt = output.get("prompt", "N/A")
        generated_text = output.get("generated_text", "")
        display_text = generated_text[:100] if generated_text else "N/A"
        print(f"[{i+1}] Prompt: {prompt!r}")
        print(f"    Generated: {display_text!r}...\n")

    return PARQUET_OUTPUT_PATH

