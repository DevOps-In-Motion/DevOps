# TODOs

## Open

- Optional write-up: Teleport AuthN/AuthZ design notes (CSR lifecycle, tradeoffs) — beyond CSR `nginx-deployer` coverage in `docs/architecture.md`
- Install Gatekeeper in lab if/when ready to enforce k8s/oidc/policy constraints live

## Done

- Traffic path: client → Gateway → HTTPRoute → Service → Pods (Gateway API only for ingress)
- Tab title → NYAN CAT
- Platform: MetalLB quietly backs Gateway address on bare metal (not an alternate ingress)
- Fixes 6–11 + bring-up blockers 1–5
- Static site stars.gif (5s) + pirate.gif; recreate path hardened
- Optional `make share` (ngrok)
- architecture.excalidraw + architecture.md: MetalLB VIP, CSR auth, OIDC groups, Gatekeeper
- OIDC IdP-agnostic package (`k8s/oidc/`): durable kubeadm ClusterConfiguration extraArgs (no static-Pod patches), group RBAC tiers, Gatekeeper policies, kubelogin docs, validation
