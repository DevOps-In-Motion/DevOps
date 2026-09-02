# Architecture: prefill/decode, prefix caching, continuous batching

Refactor applied against the Ray Data batch scaffold + a new Ray Serve path.
Principles from `vllm-ray-architecture-refactor-prompt.md`.

---

## 1. Prefill → decode (not one opaque call)

### Online path (`serving/app.py`)

| Stage | Where | Metric |
|-------|--------|--------|
| **ADMIT** | `generate_stream` constructs `StreamLatencyTracker` | TTFT clock starts |
| **ROUTE** | Ray Serve → one `VLLMEngineReplica` | Ray places the request; does not run isolated `LLM.generate()` tasks |
| **QUEUE** | `AsyncLLMEngine.generate(...)` | Engine scheduler admits work |
| **PREFILL** | First non-empty token delta | **TTFT** = first_token_at − admitted_at |
| **DECODE** | Subsequent deltas | **ITL/TPOT** = gaps between tokens |
| **STREAM** | Async generator yields SSE JSON lines | Client sees tokens before completion |

Entry-point comment block lives at the top of `serving/app.py`.

### Offline batch path (`batch_inference.py`)

Ray Data `build_processor` still **materializes full completions** per row (Parquet job). That is appropriate for offline batch, but it does **not** expose TTFT/ITL to a client. Within each GPU replica, vLLM still runs prefill+decode under continuous batching. Use `scripts/bench_prefix_cache.py` or the Serve path for latency metrics.

### Model / chat-template pinning

`model_config.yaml` tracks together:

- `model.source` + `revision`
- `tokenizer_revision`
- `chat_template_version`

Loaded via `config.load_model_config()`; env overrides available.

---

## 2. Prefix caching (APC) + prompt layout

### Engine

Every engine instantiation sets:

- `enable_prefix_caching=True` (`model_config.yaml` / `config.vllm_engine_kwargs` / batch `engine_kwargs`)
- Confirmed in `batch_inference.py` and `serving/app.py`

### Prompt assembly (`prompts.py`)

**Before:** system + user only; no documented ordering; easy to prepend dynamic junk later.

**After:** `assemble_messages()` / `messages_for_batch_row()` enforce:

1. Stable system  
2. Stable few-shots  
3. Retrieved docs (optional)  
4. Tenant/session context (optional)  
5. History (optional)  
6. Current user question  
7. Optional metadata **footer only** (timestamps/UUIDs — never at the front)

### `cache_salt`

- **Batch / single-tenant demo:** not used — stated in `batch_inference.py` and Serve replica init.  
- **Multi-tenant online:** `MULTI_TENANT=1` + `CACHE_SALT_HMAC_SECRET`; salt = HMAC(tenant_id) via `metrics.server_side_cache_salt` (never client-supplied).

### Three caches (do not conflate)

| Cache | What it is | Where |
|-------|------------|--------|
| **KV cache** | Attention state for the *current* generation | GPU / vLLM, ephemeral |
| **Prefix cache (APC)** | Reuse of KV blocks *across requests* with identical prefix | GPU / vLLM |
| **Response/application cache** | Cached *outputs* (e.g. Redis) | App layer — **not present** in this project; must not substitute for conversation DB or APC |

### Prefix-cache hit rate

`metrics.extract_prefix_cache_stats` probes engine stats on stream completion (best-effort across vLLM versions). Prefer Prometheus `/metrics` from the engine in production.

---

## 3. Continuous batching (do not fight the scheduler)

| Requirement | Status |
|-------------|--------|
| One engine instance per replica handles all requests for that replica | `VLLMEngineReplica` holds a single `AsyncLLMEngine` |
| No artificial serialization | `max_ongoing_requests` default **64** (not 1) |
| Ray routes to replica; engine schedules tokens | Documented in `serving/app.py` |
| Chunked prefill | `enable_chunked_prefill=True` in config + batch kwargs |
| Engine-level signals | Stream end emits TTFT/ITL; prefix hit probe; GPU util alone is insufficient — extend with Prometheus in follow-up |

### Known gap (not fixed — out of scope)

If `NUM_REPLICAS>1` or Ray Data `concurrency>1`, default routing is **not** cache-locality-aware. Fleet Endpoint-Picker / llm-d style routing is an optional follow-up.

---

## Explicit non-goals (unchanged)

- Prefill/decode disaggregation  
- Multi-node TP/PP / LeaderWorkerSet  
- Cache-aware fleet load balancing  

---

## Benchmarks

Run on a GPU host:

```bash
python scripts/bench_prefix_cache.py
```

Expect later TTFT ≤ early TTFT on a repeated shared prefix when APC is on. Char-level token counting in the bench is approximate; Serve SSE `ttft_s` / `mean_itl_s` are the intended production signals.

*(Numbers not filled here — requires GPU in CI/dev environment.)*

---

## Found but not fixed

| Item | Reason |
|------|--------|
| Cache-locality-aware multi-replica routing | Out of scope (optional follow-up) |
| Prefill/decode disaggregation | Out of scope |
| Full Prometheus export of queue depth / KV pressure / tokens-per-step | Needs product/ops input; probe helper only for now |
| Ray Data offline path cannot stream TTFT to clients | Batch semantics; use Serve for online |
| Exact vLLM `cache_salt` kwarg surface varies by version | Best-effort; multi-tenant path may need pin bump |
