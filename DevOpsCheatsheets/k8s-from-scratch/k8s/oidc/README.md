# OIDC (IdP-agnostic) for this kubeadm lab

See **[`docs/README.md`](docs/README.md)** for full docs.

```text
k8s/oidc/
  placeholders.env.example
  apiserver/                   # kubeadm ClusterConfiguration (durable OIDC flags)
  rbac/                        # admin: one NAMESPACE + 3 group tiers
  policy/                      # Gatekeeper
  docs/
```

**Model (matches nginx-app admin/deployer split):**

- **platform-admin** — cluster-wide; creates namespaces / Roles / bindings  
- **namespace-dev** — write inside that one `${NAMESPACE}` (default `nginx-app`)  
- **readonly-viewer** — read inside the **same** namespace  

```bash
cp k8s/oidc/placeholders.env.example k8s/oidc/placeholders.env
bash k8s/oidc/apiserver/render-kubeadm-oidc.sh
bash k8s/oidc/apiserver/apply-oidc-apiserver.sh
bash k8s/oidc/rbac/apply-rbac.sh
bash k8s/oidc/policy/apply-policy.sh              # Gatekeeper already installed
bash k8s/oidc/docs/validate.sh
```
