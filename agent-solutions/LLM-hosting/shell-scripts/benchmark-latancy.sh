MODEL_ID = "openai/gpt-oss-120b"
CONTAINER_NAME="vllm-demo"

# Evaluates single-request performance without parallelism 
# (`tensor-parallel=1`). It measures prompt processing and token generation latency for individual requests, highlighting baseline performance without concurrency or batching effects, ideal for low-load scenarios.
!vllm bench latency \
    --model {MODEL_ID} \
    --input-len 4096 \
    --output-len 1024 \
    --tensor-parallel 1 