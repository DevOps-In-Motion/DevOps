# RaSCaaS cluster prerequisites (`helm/_crds`)

Apply manifests in this order. **Gateway API CRDs must exist before** `gateway/rascaas-gateway-*.yaml` — otherwise you will see:

```text
no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
no matches for kind "TargetGroupConfiguration" in version "gateway.k8s.aws/v1beta1"
no matches for kind "LoadBalancerConfiguration" in version "gateway.k8s.aws/v1beta1"
```

RaSCaaS manifests here are **not** Helm CRDs for the chart; they are cluster/namespace prerequisites (namespace, gateway, secrets, service accounts).

---

## 0. Kubernetes context

Do not use a placeholder context name. List and select your EKS context:

```bash
kubectl config get-contexts
kubectl config use-context <your-eks-context>   # e.g. arn:aws:eks:us-west-2:650251729525:cluster/qa-kovr
kubectl cluster-info
```

---

## 1. Cluster-level Gateway API CRDs (required once per cluster)

RaSCaaS needs:

| CRD (examples) | Source |
|----------------|--------|
| `gateways.gateway.networking.k8s.io`, `httproutes.gateway.networking.k8s.io`, … | Kubernetes Gateway API |
| `targetgroupconfigurations.gateway.k8s.aws`, `loadbalancerconfigurations.gateway.k8s.aws` | AWS Load Balancer Controller |

### Install Gateway API CRDs (LBC v3.2.2)

```bash
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.2.2/config/crd/gateway/gateway-crds.yaml"
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.2.2/config/crd/gateway/gatewayclass.yaml"
kubectl get crd | grep -E 'gateway|targetgroup|loadbalancer'
kubectl get gatewayclass alb
```

**Optional:** If the cluster was set up with Kovr `grommet/helm-support`, `./install-gateway-class.sh` applies the same CRDs from vendored YAML and restarts LBC.

### Verify CRDs

```bash
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io
kubectl get crd targetgroupconfigurations.gateway.k8s.aws
kubectl get crd loadbalancerconfigurations.gateway.k8s.aws
kubectl get gatewayclass alb
```

If LBC was already running before CRDs were installed, restart it so ALB Gateway API is enabled:

```bash
kubectl rollout restart deployment -n kube-system aws-load-balancer-controller
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s
```

LBC must be installed with `ALBGatewayAPI` enabled (see `platform-testing/support/sh/cheatsheet.sh` or grommet LBC Helm values).

---

## 2. RaSCaaS namespace and secrets

```bash
cd platform-testing/RasCaaS

python3 scripts/render-plain-secrets.py   # or edit helm/_crds/secrets/plain-secrets.yaml

kubectl apply -f helm/_crds/namespace.yaml
kubectl apply -f helm/_crds/service-accounts/    # plain mode: IRSA optional
kubectl apply -f helm/_crds/secrets/plain-secrets.yaml
```

CSI mode: apply `secrets/spc.yaml` instead of `plain-secrets.yaml` (see `secrets/README.md`).

---

## 3. RaSCaaS Gateway (ALB)

See [`gateway/README.md`](gateway/README.md).

**QA (`rascaas.qa.kovr.ai`):**

```bash
kubectl apply -f helm/_crds/gateway/rascaas-gateway-base.yaml
# Edit REPLACE_WITH_IAM_SERVER_CERT_ARN in rascaas-gateway-https.qa.yaml, then:
kubectl apply -f helm/_crds/gateway/rascaas-gateway-https.qa.yaml
kubectl get gateway rascaas-gateway -n rascaas
```

Point DNS `rascaas.qa.kovr.ai` at the ALB address in `status.addresses`.

**Other hosts:** use `rascaas-gateway-https.template.yaml` with `sed` (documented in `gateway/README.md`).

---

## 4. Helm chart

```bash
export ECR_IMAGE=650251729525.dkr.ecr.us-west-2.amazonaws.com/rascaas:latest

helm upgrade --install rascaas ./helm/rascaas -n rascaas \
  --set secrets.mode=plain \
  --set fastapi.image="$ECR_IMAGE" \
  --set fastapi.env.GITHUB_APP_ID="3825031" \
  --set fastapi.env.GITHUB_INSTALLATION_ID="134904362" \
  --set fastapi.env.OIDC_ISSUER_URL="https://<idp>/realms/<realm>" \
  --set fastapi.env.OIDC_CLIENT_ID="platform-ui" \
  --set fastapi.env.APP_BASE_URL="https://${RASCAAS_HOST}" \
  --set fastapi.env.GITHUB_DISPATCH_REPO=kovr-ai/platform \
  --set fastapi.env.DEFAULT_WORKFLOW=uat-deploy.yml \
  --set fastapi.env.TRUST_OAUTH2_PROXY_IDENTITY=true \
  --set oauth2proxy.oidcIssuerUrl="https://<idp>/realms/<realm>" \
  --set oauth2proxy.clientId="platform-ui" \
  --set oauth2proxy.redirectUrl="https://${RASCAAS_HOST}/oauth2/callback" \
  --set oauth2proxy.cookieSecure=true
```

---

## 5. Verify

```bash
kubectl get pods,svc,httproute -n rascaas
kubectl get gateway rascaas-gateway -n rascaas
```

---

## Apply order (checklist)

| Step | What |
|------|------|
| 0 | `kubectl config use-context` (real name, not a placeholder) |
| 1 | Gateway API + AWS LBC gateway **CRDs** + `GatewayClass` **`alb`** |
| 2 | `namespace.yaml` |
| 3 | `service-accounts/` |
| 4 | `secrets/plain-secrets.yaml` (or `spc.yaml`) |
| 5 | `gateway/rascaas-gateway-base.yaml` |
| 6 | `gateway/rascaas-gateway-https.template.yaml` (sed host + cert ARN) |
| 7 | `helm upgrade --install` chart |

---

## Related docs

- `secrets/README.md` — plain vs CSI secrets
- `../README.md` — GitHub App, local Docker, full install index
- `platform-testing/grommet/helm-support/install-gateway-class.sh` — Kovr Gateway API platform install
- `platform-testing/grommet/docs-site/content/docs/09-kovr-prerequisites/` — full cluster prerequisite runbook
