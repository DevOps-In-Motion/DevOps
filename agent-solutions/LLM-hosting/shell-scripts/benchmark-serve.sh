MODEL_ID = "openai/gpt-oss-120b"
CONTAINER_NAME="vllm-demo"

!vllm bench serve \
    --model {MODEL_ID} \
    --dataset-name random \
    --dataset-name random \
    --random-input-len 4096 \
    --random-output-len 1024 \
    --max-concurrency 8 \
    --num-prompts 80 \
    --ignore-eos \
    --percentile_metrics ttft,tpot,itl,e2el