import os

from .cluster import *

ENV = os.getenv()

NUM_GPUS = ENV["NUM_GPUS"]

result = run_distributed_inference.distributed()
parquet_path = result[0] if NUM_GPUS > 1 else result
print(f"\n✓ Inference complete! Results saved to: {parquet_path}")