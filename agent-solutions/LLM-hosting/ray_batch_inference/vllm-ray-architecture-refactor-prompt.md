# Agent Prompt: Refactor vLLM + Ray Architecture for Prefill/Decode Awareness, Prefix Caching, and Continuous Batching

## Context

You are refactoring an existing vLLM + Ray project. The current architecture treats
inference as an undifferentiated request/response service. This is incorrect for LLM
serving and is costing us throughput, latency predictability, and GPU efficiency.

You must apply the following three architectural principles, drawn from a reference
architecture document. Do not treat these as suggestions — they are structural
requirements. Read the entire prompt before making changes, since the three sections
below interact with each other (batching decisions depend on knowing prefill vs.
decode; prefix caching depends on prompt layout, which affects batching).

---

## 1. Model the request lifecycle as prefill-then-decode, not as one opaque call

**Problem with current code (likely):** if requests are handled as a single blocking
"generate full completion" call, you cannot distinguish the compute-bound prefill
phase from the memory-bandwidth-bound decode phase, cannot stream tokens, and cannot
reason about Time To First Token (TTFT) vs. inter-token latency separately.

**Required changes:**

- Audit every code path that calls into vLLM (whether via `LLM.generate()`,
  `AsyncLLMEngine`, or a Ray actor wrapping either) and confirm requests are
  submitted as streaming generations, not batch-and-wait calls. If any code path
  currently waits for a full completion before returning to the caller, convert it to
  an async generator / token stream.
- Introduce two explicit latency metrics wherever a request is timed:
  - **TTFT (Time To First Token):** time from request admission to the first token
    emitted. This is dominated by prompt length and queueing, not decode speed.
  - **Inter-token latency (ITL) / Time Per Output Token (TPOT):** time between
    successive tokens once generation has started.
  Do not conflate these into a single "request latency" metric — they have different
  causes and different remediation.
- Confirm the chat template and tokenizer versions are pinned together with the model
  in whatever config/manifest defines a deployment. If the project renders chat
  messages into a prompt string before tokenization (as any chat-style API must),
  verify that template changes are versioned alongside the model weights, since a
  template change silently changes model input even when the API request is
  identical. Add this as an explicit field in your model/version config if it is not
  already tracked.
- If the Ray layer currently treats "one request = one Ray task", re-examine this: a
  single vLLM engine instance batches multiple requests together at the token level
  (see section 3). Ray's job should be to route/place requests onto the correct vLLM
  engine actor, not to run one engine invocation per request in isolation.

**Deliverable for this section:** a short internal doc or code comment block at the
entry point of the serving path stating (a) which stage the request is in at each
step, (b) where TTFT is measured, (c) where ITL is measured.

---

## 2. Implement and correctly configure prefix caching (Automatic Prefix Caching), and restructure prompts to maximize hit rate

**Problem with current code (likely):** if prompts are being built with dynamic
content (timestamps, request IDs, session-specific values) prepended or interleaved
near the front of the prompt, the KV cache prefix hash changes on every request even
when most of the prompt is semantically identical. This silently disables prefix
caching and forces full re-prefill on every call.

**Required changes:**

- Confirm `--enable-prefix-caching` (or the equivalent `enable_prefix_caching=True`
  engine arg) is set on every vLLM engine instantiation in this project. If it is not
  currently enabled, enable it and benchmark before/after TTFT on repeated-prefix
  workloads.
- Audit the prompt construction code (wherever messages are assembled before being
  sent into the tokenizer/chat template) and enforce this ordering, top to bottom:
  1. Stable system instructions (rarely or never change)
  2. Stable shared few-shot examples / static context (rarely changes)
  3. Stable retrieved/document context, if RAG is in use (changes per query but is
     often front-loadable if the same documents are reused across a session)
  4. Tenant- or session-specific context (varies)
  5. Conversation history (varies, grows over time)
  6. Current user question (always varies, must be last)
  Anything highly dynamic (timestamps, request UUIDs, nonces) must never appear near
  the front of the prompt. If such values are currently injected into a system
  prompt header, move them to the end or remove them if unnecessary. Do not distort
  prompt semantics purely to gain cache hits, but do not tolerate unnecessary
  front-loaded variation either — flag any you find as a specific before/after diff.
- If this project is multi-tenant (multiple users, sessions, or logical
  tenants sharing engine instances): implement a per-request cache-namespace value
  (vLLM's `cache_salt` parameter or equivalent) so that unrelated tenants/sessions
  cannot reuse each other's cached KV prefix blocks. This value must be generated
  server-side (e.g., derived via HMAC from a trusted tenant/session identity), never
  accepted as a raw client-supplied field. If the project is single-tenant/single-user,
  state explicitly in a comment why `cache_salt` is not needed, rather than silently
  omitting it.
- Add an explicit distinction in code/comments between three caches that are easy to
  conflate — do not let any of them silently substitute for another:
  - **KV cache:** in-GPU-memory attention state for tokens already processed in the
    *current* generation. Ephemeral, lives in vLLM/GPU memory only.
  - **Prefix cache:** reuse of KV blocks *across separate requests* that share an
    identical prefix. Also GPU-memory-resident, managed by vLLM.
  - **Response/application cache (if any exists in this project, e.g., Redis):** this
    is a completely different mechanism — caching an actual model output — and must
    never be assumed to be interchangeable with the above. If the project currently
    has a Redis-backed cache and the code or docs describe it as "the model cache" or
    similar, correct that terminology and confirm it is not being used as a substitute
    for durable conversation state (which must live in application DB, not in vLLM's
    ephemeral KV memory).
- Add or verify a metric for **prefix-cache hit rate**, exposed per engine instance,
  so this can actually be observed rather than assumed.

**Deliverable for this section:** a diff (or explicit list) of every prompt-assembly
function changed for ordering, plus confirmation that `cache_salt`/namespacing is
either implemented or explicitly deemed unnecessary with a stated reason.

---

## 3. Verify and correctly leverage continuous batching; do not fight the vLLM scheduler from the Ray layer

**Problem with current code (likely):** Ray is sometimes used to fan out one
model call per incoming request as an independent, isolated unit of work (e.g., one
Ray task/actor call per HTTP request, each blocking until its own generation
completes). This defeats continuous batching, which is vLLM's internal mechanism for
letting many requests share GPU time efficiently, with requests joining and leaving
an in-flight batch as they progress through prefill/decode — not a fixed batch that
starts and finishes together.

**Required changes:**

- Identify how many independent vLLM engine processes/actors this project runs, and
  confirm that all requests destined for the *same model replica* are submitted into
  a single `AsyncLLMEngine` (or equivalent) instance's request queue, not spread
  across multiple engine instances unnecessarily or run through separate blocking
  calls that prevent the internal scheduler from batching them together. One engine
  instance = one continuous-batching scheduler. Do not instantiate more engine
  instances than you have GPU-replica-worth of resources for.
- If Ray is used to parallelize this project (e.g., multiple Ray actors each wrapping
  a vLLM engine, for multiple replicas), confirm that the *routing layer* choosing
  which actor receives a given request is doing so with the understanding that:
  - The vLLM engine's internal scheduler decides which requests/tokens run in a
    given engine step (prefill admission, decode continuation, KV-cache budget).
    This is not something Ray should attempt to second-guess, override, or replicate.
  - Ray's job at this layer is one level up: deciding *which engine actor/replica* a
    new request goes to. If you have more than one replica and requests currently go
    to replicas via naive round robin, note this as a known limitation (see "Optional
    follow-up" below) rather than attempting to fix it as part of this pass unless
    explicitly asked.
- Confirm GPU utilization is not being wasted through unintended serialization. In
  particular, check for:
  - Any `asyncio` blocking calls (e.g., accidental synchronous `.result()` waits) in
    the request-submission path that would prevent multiple in-flight requests from
    reaching the engine concurrently.
  - Any Ray actor configured with `max_concurrency=1` or similar that would
    serialize calls into a vLLM engine that is otherwise capable of handling many
    concurrent async requests via continuous batching.
- If long prompts and short interactive decode work are mixed in this project's
  traffic, confirm chunked prefill is enabled (`enable_chunked_prefill=True` or
  equivalent) so a long prefill doesn't stall latency-sensitive decode steps for
  other in-flight requests on the same engine.
- Add or verify these engine-level metrics are exposed, since GPU utilization alone
  is not a sufficient signal for either debugging or (later) autoscaling: queued
  request count, running sequence count, KV-cache utilization/pressure, tokens
  processed per engine step.

**Deliverable for this section:** confirmation (with code references) that (a) one
engine instance handles all requests for one replica without artificial
serialization, (b) chunked prefill is configured appropriately for this project's
traffic shape, (c) the listed engine-level metrics are exposed.

---

## Explicit non-goals for this pass

Do not implement the following unless separately instructed — they are out of scope
for this refactor and are called out here only to prevent scope creep:

- Prefill/decode disaggregation (separate prefill vs. decode worker pools with KV
  transfer over the network). This is a fleet-level optimization that only pays off
  once prefill and decode contention is measured and confirmed as a bottleneck.
- Multi-node tensor/pipeline parallelism, LeaderWorkerSet-style gang scheduling, or
  any change to how many GPUs a single replica spans.
- Fleet-level inference-aware routing (e.g., llm-d / Endpoint Picker style
  cache-locality-aware load balancing across replicas). Only relevant once there are
  multiple replicas and naive round-robin routing is confirmed to be causing
  cache-locality loss in practice.

## Optional follow-up (flag, do not implement)

If, during this pass, you discover the project already has multiple vLLM replicas
behind naive round-robin routing (via Ray or otherwise), flag this explicitly as a
known gap rather than fixing it now: at that scale, plain load balancing is not
sufficient because replicas are not cache-equivalent (one may hold a hot prefix
cache for a given tenant/session while another doesn't). Note it for a future pass
rather than expanding this refactor's scope.

---

## Deliverables summary

At the end of this task, produce:

1. A summary of what was changed in each of the three sections above, with file/line
   references.
2. Before/after benchmark numbers if feasible (TTFT and ITL under a repeated-prefix
   workload, prefix-cache hit rate, GPU utilization) — even a rough local benchmark
   is more useful than none.
3. An explicit list of anything found but *not* fixed, with a one-line reason
   (e.g., "out of scope for this pass," "needs product input," "needs multi-replica
   setup to test").
