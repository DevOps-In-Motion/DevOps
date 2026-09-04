MODEL_ID = "openai/gpt-oss-120b"
CONTAINER_NAME="vllm-demo"


# Focuses on maximizing token generation speed under hardware optimization 
# (e.g., 4-way tensor parallelism). 
# It stresses batch processing efficiency by g
# generating fixed-length outputs, measuring raw tokens/second, and 
#ignoring concurrency dynamics to benchmark peak computational throughput.

# `Batch processing: Batch processing groups multiple requests together to be processed 
# simultaneously by the AI. This maximizes hardware efficiency and increases overall 
# throughput, but it can increase the latency for any individual request. It is ideal 
# for non-interactive, high-volume tasks. 

# `--tensor-parallel n` which `n` value set the card number we adopt to serve the model.
!vllm bench throughput \
    --model {MODEL_ID} \
    --dataset-name random \
    --input-len 4096 \
    --output-len 1024 \
    --num-prompts 4 \
    --tensor-parallel 1 