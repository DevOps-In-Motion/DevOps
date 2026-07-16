# OIDC validation / test plan

No production IdP required. Prefer certificate admin kubeconfig for steps that mutate the control plane.

## A. Apiserver picked up OIDC flags

After `make destroy && make up` (or `apply-oidc-apiserver.sh`):

```bash
vagrant ssh controlplane -c \
  'sudo grep -E "oidc-(issuer-url|client-id|groups-prefix|username-prefix|ca-file)" /etc/kubernetes/manifests/kube-apiserver.yaml'

# Flags must match k8s/oidc/placeholders.env / .example
vagrant ssh controlplane -c \
  'kubectl -n kube-system get cm kubeadm-config -o yaml | grep -A2 oidc || true'
```

Expect: all seven `--oidc-*` args present; apiserver Pod Running; `/readyz` ok.

## B. RBAC group bindings

```bash
set -a; source k8s/oidc/placeholders.env.example; set +a
bash k8s/oidc/rbac/apply-rbac.sh

kubectl get clusterrolebinding oidc-platform-admin -o yaml | grep -A3 subjects
kubectl -n "${NAMESPACE}" get rolebinding oidc-namespace-dev,oidc-readonly-viewer -o yaml | grep -A3 subjects
```

Impersonation dry-run (no IdP):

```bash
PFX="${OIDC_GROUPS_PREFIX}"
kubectl auth can-i '*' '*' --as=oidc-test --as-group="${PFX}${GROUP_PLATFORM_ADMIN}"

kubectl auth can-i create deployments -n "${NAMESPACE}" \
  --as=oidc-dev --as-group="${PFX}${GROUP_NAMESPACE_DEV}"
kubectl auth can-i create nodes \
  --as=oidc-dev --as-group="${PFX}${GROUP_NAMESPACE_DEV}"   # expect no

kubectl auth can-i get pods -n "${NAMESPACE}" \
  --as=oidc-ro --as-group="${PFX}${GROUP_READONLY_VIEWER}"
kubectl auth can-i delete pods -n "${NAMESPACE}" \
  --as=oidc-ro --as-group="${PFX}${GROUP_READONLY_VIEWER}" # expect no
```

## C. Gatekeeper rejects invalid cases

Requires Gatekeeper installed, then `bash k8s/oidc/policy/apply-policy.sh`.

```bash
kubectl create ns gk-test --dry-run=client -o yaml | kubectl apply -f -
cat <<'EOF' | kubectl apply -f - ; echo "exit=$?"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: bad-wild, namespace: gk-test }
rules: [{ apiGroups: ["*"], resources: ["*"], verbs: ["*"] }]
EOF
# expect admission webhook denial

kubectl -n gk-test create sa local-sa --dry-run=client -o yaml | kubectl apply -f -
cat <<EOF | kubectl apply -f - ; echo "exit=$?"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: bad-xns, namespace: gk-test }
subjects:
  - kind: ServiceAccount
    name: default
    namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: oidc-readonly-viewer
EOF

cat <<EOF | kubectl --as=oidc-dev --as-group="${OIDC_GROUPS_PREFIX}${GROUP_NAMESPACE_DEV}" apply -f - ; echo "exit=$?"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: should-fail-crb }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: view }
subjects: [{ kind: Group, name: oidc:nobody, apiGroup: rbac.authorization.k8s.io }]
EOF
```

Cleanup: `kubectl delete ns gk-test --wait=false`

## D. Client OIDC (when IdP exists)

See [README.md](README.md) §4 — `kubectl auth whoami` must show username/groups with configured prefixes.
