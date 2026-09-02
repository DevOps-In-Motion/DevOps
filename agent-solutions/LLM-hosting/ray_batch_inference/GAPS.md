# Gaps and next steps

Context: self-hosted **vLLM + Ray** only (no Bedrock), customer traffic (~**200** customers, ~**25** in-flight steady, weekly/monthly spikes), **one replica → one exclusive GPU** (or MIG slice that fits the full model), many requests → one engine via continuous batching.

Related: [`architecture.md`](architecture.md), [`model_config.yaml`](model_config.yaml).

---

## Gaps

### Product / capacity

- No locked **SLO** (p95/p99 TTFT, max queue wait, behavior at ceiling: wait vs 429).
- No measured **in-flight-per-GPU** for production prompts (25 steady / spike multipliers are still estimates).
- **Model not pinned** for prod (Distill **14B** vs **32B**; chat template / revision still smoke defaults in config).
- No **overload policy** without Bedrock (admission control, fair queue per customer).
- **Multi-tenant isolation** only sketched (`cache_salt`); not wired to real customer IDs / quotas.

### Platform (scaffold vs production)

- Local Ray Serve / batch only; no **EKS / KubeRay**, GPU node pools, or cluster autoscale.
- No **queue ↔ Serve** adapter for AI workers (still Bedrock-shaped integration).
- No stable **OpenAI-compatible** API contract for workers (SSE demo ≠ production client).
- **Replica routing** is naive if `NUM_REPLICAS > 1` (not cache-locality-aware) — flagged in architecture, unfixed.
- Prefill/decode disaggregation and multi-node TP are out of scope; still a future gap if load warps that way.
- **MIG / GPU sharing** not designed; risk of overcommit if heavy replicas share one physical GPU.

### Observability / ops

- No full **Prometheus** story: queue depth, KV %, running seqs, tokens/step, prefix-cache hit rate.
- No **GPU autoscale** triggers (queue age / TTFT / KV) or warm pool for sharp spikes.
- No **load test** harness for 25 → 50–75 in-flight reasoning traffic.
- No **runbooks**: OOM, slow cold start, replica drain, model upgrade.

### Security / delivery

- Authn/z to Serve, network isolation, secrets (HF tokens, etc.).
- Image build/CD for CUDA + vLLM + Ray; multi-AZ / disruption budgets for GPU nodes.
- Cost model: floor 2–3 GPUs vs ceiling ~6–8 with no managed spill.

### Docs / repo

- Sizing guidance was discussed in planning; keep this file + config in sync as decisions land.
- `model_config.yaml` still defaults to tiny Qwen 0.5B for local smoke tests.

---

## Next steps (ordered)

1. **Decide model:** Distill **14B** (default) or **32B**; pin HF id + `chat_template_version` in `model_config.yaml`.
2. **Define SLOs + ceiling policy:** e.g. p95 TTFT, max wait, 429 when at max replicas.
3. **Bench one GPU:** max stable in-flight for real prompt lengths →  
   `floor ≈ ceil(25 / per_gpu) + HA` (expect **2×14B** or **3×32B**).
4. **Spike profile:** agree 2×/3× (or measured weekly/monthly peaks) → set **autoscale ceiling** (~4–8).
5. **Worker adapter:** queue consumer → vLLM/Serve HTTP (OpenAI-compatible); remove Bedrock path.
6. **Deploy path:** KubeRay or Serve on a GPU node group; **1 pod/replica = 1 GPU**; no fractional GPU for this model class.
7. **Metrics + alerts:** TTFT, ITL, KV util, queue age, prefix hit rate → scale signals.
8. **Load test** normal 25 + synthetic peak; tune `max_ongoing_requests` / `max_model_len`.
9. **Tenancy:** server-side `cache_salt` from customer id + per-tenant concurrency caps.
10. **Optional later:** cache-aware routing across replicas; MIG only if model/quant fits a slice.

---

## Snapshot target (current planning numbers)

| Item | Target |
|------|--------|
| Steady | ~25 in-flight, ~200 customers |
| Floor | **2 GPUs (14B)** or **3 (32B)** |
| Ceiling | **~4–8** exclusive-GPU replicas |
| Pattern | Many requests → one engine; scale load with more replicas, not GPU oversubscribe |

Formula after first bench:

```text
replicas_needed ≈ ceil(peak_in_flight / measured_per_gpu) + 1
```

Set autoscale ceiling from real weekly/monthly peaks.
