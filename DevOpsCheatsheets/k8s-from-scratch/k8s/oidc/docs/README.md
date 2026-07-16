# OIDC authentication (IdP-agnostic)

No Keycloak/Dex/Okta is provisioned here. Wire a real IdP later by editing
`k8s/oidc/placeholders.env` and re-rendering — **kubeadm `ClusterConfiguration`
`apiServer.extraArgs` is the source of truth**, so config survives
`make destroy` / `make up` without hand-editing static Pods.

## Layout

| Path | Purpose |
| --- | --- |
| [`placeholders.env.example`](../placeholders.env.example) | All find/replace tokens |
| [`apiserver/`](../apiserver/) | kubeadm ClusterConfiguration template + render/apply |
| [`rbac/`](../rbac/) | platform-admin / namespace-dev / readonly-viewer |
| [`policy/`](../policy/) | Gatekeeper templates + constraints |
| [`validation.md`](validation.md) / [`validate.sh`](validate.sh) | Test plan |

## 1. Apiserver OIDC (durable)

Flags live in kubeadm:

- `--oidc-issuer-url`
- `--oidc-client-id`
- `--oidc-username-claim`
- `--oidc-groups-claim`
- `--oidc-username-prefix`
- `--oidc-groups-prefix`
- `--oidc-ca-file`

**Bring-up:** `scripts/vm-controlplane-init.sh` sources `k8s/oidc/placeholders.env`
(or `.example`) and embeds those values into `kubeadm init --config …`.

**Update existing CP (no manifest sed):**

```bash
cp k8s/oidc/placeholders.env.example k8s/oidc/placeholders.env
# edit issuer / client-id / CA when IdP is ready
bash k8s/oidc/apiserver/render-kubeadm-oidc.sh
bash k8s/oidc/apiserver/apply-oidc-apiserver.sh
# or on the node: CP_LOCAL=1 bash k8s/oidc/apiserver/apply-oidc-apiserver.sh
```

`apply-oidc-apiserver.sh` runs:

`kubeadm init phase control-plane apiserver --config …`

so kubelet’s static Pod is **regenerated from ClusterConfiguration**, not patched.

### Static Pod restart & rollout order

1. Keep **certificate** admin kubeconfig (`admin.conf` / `make context-host`) —
   OIDC tokens are not required for break-glass.
2. Change **one** control plane at a time when HA; wait for `/readyz` before the next.
3. kubelet recreates `kube-apiserver-*` when the manifest under
   `/etc/kubernetes/manifests/` changes (written by kubeadm phase).
4. Do **not** remove local `system:masters` access before confirming OIDC + RBAC.
5. Place IdP CA at `${OIDC_CA_FILE}` (bootstrap placeholder CA is installed until then).

## 2. RBAC tiers

Admin applies the manifests (creates the namespace + Roles + bindings). Developers
never create namespaces — they only operate inside `${NAMESPACE}` (default
`nginx-app`, same as this lab).

| Tier | Who | Scope |
| --- | --- | --- |
| platform-admin | IdP group `${OIDC_GROUPS_PREFIX}${GROUP_PLATFORM_ADMIN}` | cluster-wide |
| namespace-dev | IdP group `${OIDC_GROUPS_PREFIX}${GROUP_NAMESPACE_DEV}` | write in `${NAMESPACE}` |
| readonly-viewer | IdP group `${OIDC_GROUPS_PREFIX}${GROUP_READONLY_VIEWER}` | read in `${NAMESPACE}` |

```bash
set -a; source k8s/oidc/placeholders.env; set +a
bash k8s/oidc/rbac/apply-rbac.sh
```

`--oidc-groups-prefix` **must** match RoleBinding subjects
(example: prefix `oidc:` + group `namespace-devs` → `oidc:namespace-devs`).

## 3. Gatekeeper (assumes already installed)

```bash
bash k8s/oidc/policy/apply-policy.sh
```

- Block ClusterRoleBinding create/update unless requester is in platform-admin
  group (or `system:masters` break-glass).
- Deny `*` verbs/resources on namespace-scoped `Role`.
- Deny RoleBinding ServiceAccount subjects that reference another namespace.

## 4. kubectl + kubelogin (after a real IdP exists)

Install [kubelogin](https://github.com/int128/kubelogin) (`kubectl oidc-login`).

```bash
# Placeholders — replace with real IdP values from placeholders.env
export OIDC_ISSUER_URL='${OIDC_ISSUER_URL}'
export OIDC_CLIENT_ID='${OIDC_CLIENT_ID}'

kubectl config set-credentials oidc-user \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url="${OIDC_ISSUER_URL}" \
  --exec-arg=--oidc-client-id="${OIDC_CLIENT_ID}" \
  --exec-arg=--oidc-extra-scope=groups \
  --exec-arg=--oidc-extra-scope=email

kubectl config set-context oidc-context \
  --cluster=kubernetes \
  --user=oidc-user

kubectl config use-context oidc-context
kubectl auth whoami
```

If the IdP uses a private CA, pass kubelogin’s CA flags (or trust the CA in the OS store)
matching `${OIDC_CA_FILE}` contents.

## Plug in a real IdP later

1. Put IdP CA at `${OIDC_CA_FILE}` on each control plane (or regenerate via render + apply).
2. Set `OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`, claims, and group names in `placeholders.env`.
3. `bash k8s/oidc/apiserver/render-kubeadm-oidc.sh && bash k8s/oidc/apiserver/apply-oidc-apiserver.sh`
4. Re-apply RBAC/policy if group/namespace tokens changed.
5. Configure kubelogin as above — **no rebuild of the lab required**.
