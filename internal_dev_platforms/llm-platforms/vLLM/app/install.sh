%pip install --force-reinstall --no-cache-dir --no-deps "https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.6cxx11abiFALSE-cp312-cp312-linux_x86_64.whl"
%pip install "transformers<4.54.0"
%pip install "vllm==0.8.5.post1"
%pip install "ray[data]>=2.47.1"  # Required for ray.data.llm API
%pip install "opentelemetry-exporter-prometheus"
%pip install "optree>=0.13.0"
%pip install hf_transfer
%pip install "numpy==1.26.4"
%restart_python