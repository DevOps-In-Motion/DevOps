# RaSCaaS Gateway (AWS LBC + Gateway API)

## Files

| File | When to apply |
|------|----------------|
| [`rascaas-gateway-base.yaml`](rascaas-gateway-base.yaml) | First — HTTP :80, TargetGroupConfiguration, LoadBalancerConfiguration |
| [`rascaas-gateway-https.qa.yaml`](rascaas-gateway-https.qa.yaml) | QA — HTTPS :443, hostname `rascaas.qa.example.com` + ACM `*.qa.example.com` |
| [`rascaas-gateway-https.template.yaml`](rascaas-gateway-https.template.yaml) | Other envs — `sed` placeholders `__RASCAAS_GATEWAY_HOSTNAME__`, `__IAM_SERVER_CERT_ARN__` |

## LBC attach (required on LBC v3.4 / QA)

Use **`Gateway.spec.infrastructure.parametersRef`** → `LoadBalancerConfiguration` (same as Drawhaus/Excalidraw and [LBC docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/customization/)).

Do **not** rely on annotation `gateway.k8s.aws/load-balancer-configuration` alone — LBC ignores `scheme: internet-facing` and provisions an **`internal-*`** ALB (Mac curl hangs).

## QA apply order

```bash
cd ./app/RasCaaS

# After Gateway API CRDs + namespace rascaas (see ../README.md under _crds/)

kubectl apply -f helm/_crds/gateway/rascaas-gateway-base.yaml
kubectl apply -f helm/_crds/gateway/rascaas-gateway-https.qa.yaml

kubectl get gateway rascaas-gateway -n rascaas -w
# Expect ADDRESS without "internal-" prefix and Scheme=internet-facing
```

Point **DNS** `rascaas.qa.example.com` at the ALB address in `status.addresses`.

## Must match Helm (`helm/_values/qa-install-values.yaml`)

| Layer | Field |
|-------|--------|
| Gateway HTTPS listener | `hostname: rascaas.qa.example.com` (in `rascaas-gateway-https.qa.yaml`) |
| HTTPRoutes | `gateway.hostname: rascaas.qa.example.com` |
| oauth2-proxy / FastAPI | `APP_BASE_URL`, `redirectUrl` |
| Cognito app client | Allowed callback `https://rascaas.qa.example.com/oauth2/callback` |

Then install the chart:

```bash
cd ./app/RasCaaS/helm

helm upgrade --install rascaas ./rascaas -n rascaas -f _values/qa-install-values.yaml
```

## Auth path (HTTPRoutes → ALB)

Authenticated browser traffic must hit **oauth2-proxy**, which sets identity headers and proxies to FastAPI.

| Path | Backend |
|------|---------|
| `/`, `/oauth2`, `/api/*` (via catch-all `/*`) | `oauth2proxy` |
| `/health`, `/ready`, `/api/runner` | `rascaas` (probes + GHA runner callback; no oauth2) |

Helm template: `rascaas/templates/https-routes-fastapi.yaml` (under `helm/`) — **do not** PathPrefix `/api/repos|/api/branches|/api/trigger` to FastAPI. **Do** keep `/api/runner` on FastAPI so Actions can POST progress with `RUNNER_CALLBACK_TOKEN`.

### Required ALB listener rules (QA)

After Helm + HTTPRoutes settle, the **HTTPS** listener on the rascaas ALB must look like this (lower priority number = evaluated first):

| Priority | Path patterns | Target |
|----------|---------------|--------|
| (e.g. 3) | `/api/runner`, `/api/runner/*` | **FastAPI** TG (`k8s-rascaas-rascaasa-*`) |
| 4 | `/oauth2`, `/oauth2/*` | oauth2-proxy |
| 5 | `/health`, `/health/*` | FastAPI |
| 6 | `/ready`, `/ready/*` | FastAPI |
| 7 | `/*` | oauth2-proxy |

**Critical:** `/api/runner*` must have priority **strictly less than** the catch-all `/*`. If it is missing, GHA `rascaas_notify` hits oauth2-proxy (often a Cognito login **200**), FastAPI never sees `POST /api/runner/events`, deploys stay `phase=provisioning`, and the **Failed** tab stays empty.

#### Check

```bash
export AWS_PROFILE=YOUR_AWS_PROFILE AWS_REGION=us-west-2
LB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'rascaas')].LoadBalancerArn" --output text)
HTTPS=$(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" \
  --query "Listeners[?Port==\`443\`].ListenerArn" --output text)
aws elbv2 describe-rules --listener-arn "$HTTPS" --output json \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
for r in d["Rules"]:
  if r.get("IsDefault"): continue
  paths=[]
  for c in r.get("Conditions") or []:
    if c.get("Field")=="path-pattern":
      paths=c.get("PathPatternConfig",{}).get("Values") or c.get("Values") or []
  tg=(r["Actions"][0].get("TargetGroupArn") or "").split("/")[-2] if r["Actions"][0].get("TargetGroupArn") else ""
  print(f"pri={r['Priority']} paths={paths} tg={tg}")
'
```

Expect a row with `/api/runner` (and `/api/runner/*`) on the **rascaasa** (FastAPI) target group, with priority **&lt;** the `/*` rule.

#### Fix if `/api/runner` is missing (manual create-rule)

HTTPRoute `rascaas-api-route` already declares `/api/runner`; LBC sometimes never materializes that ALB rule (priority / `SetRulePriorities` gaps). Create it by hand:

```bash
export AWS_PROFILE=YOUR_AWS_PROFILE AWS_REGION=us-west-2
LB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'rascaas')].LoadBalancerArn" --output text)
HTTPS=$(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" \
  --query "Listeners[?Port==\`443\`].ListenerArn" --output text)

# Same TG as /health and /ready (FastAPI)
TG=$(aws elbv2 describe-rules --listener-arn "$HTTPS" --output json \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
for r in d["Rules"]:
  if r.get("IsDefault"): continue
  for c in r.get("Conditions") or []:
    vals=(c.get("PathPatternConfig") or {}).get("Values") or c.get("Values") or []
    if "/health" in vals or "/health/*" in vals:
      print(r["Actions"][0]["TargetGroupArn"]); raise SystemExit
')

# Priority must be lower than catch-all /* (QA catch-all is typically 7)
aws elbv2 create-rule \
  --listener-arn "$HTTPS" \
  --priority 3 \
  --conditions \
    'Field=host-header,HostHeaderConfig={Values=[rascaas.qa.example.com]}' \
    'Field=path-pattern,PathPatternConfig={Values=[/api/runner,/api/runner/*]}' \
  --actions "Type=forward,TargetGroupArn=$TG"
```

#### Verify callbacks reach FastAPI

```bash
# After a UAT notify step, FastAPI access logs must show POST /api/runner/events
kubectl logs -n rascaas deploy/rascaas-deployment --since=10m | grep '/api/runner'
```

In Actions, `rascaas_notify: ok status=200` alone is **not** enough (oauth2 login pages also return 200). Prefer FastAPI log lines with `runner_events` / `POST /api/runner/events`.

### Stale ALB listener rules (401 on `/api/repos` while UI is signed in)

If the HTTPRoute was fixed but the browser still gets FastAPI’s “Not authenticated… localhost:4180” on `/api/repos` (while `/api/clusters` works), the **ALB still has old path rules** forwarding those APIs to the FastAPI target group.

Check:

```bash
LB_ARN=$(aws elbv2 describe-load-balancers --profile YOUR_AWS_PROFILE --region us-west-2 \
  --query "LoadBalancers[?contains(LoadBalancerName,'rascaas')].LoadBalancerArn" --output text)
HTTPS=$(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" --profile YOUR_AWS_PROFILE --region us-west-2 \
  --query "Listeners[?Port==\`443\`].ListenerArn" --output text)
aws elbv2 describe-rules --listener-arn "$HTTPS" --profile YOUR_AWS_PROFILE --region us-west-2 \
  --query 'Rules[?!IsDefault].[Priority,Conditions[?Field==`path-pattern`].Values]' --output table
```

Expect **no** `/api/repos` / `/api/branches` / `/api/trigger` rules (only `/oauth2`, `/health`, `/ready`, `/api/runner*`, `/*`).

Delete stale rules (replace ARNs from describe-rules), then hard-refresh the app:

```bash
aws elbv2 delete-rule --rule-arn '<listener-rule-arn>' --profile YOUR_AWS_PROFILE --region us-west-2
```

Prevent recurrence — from `platform-testing/RasCaaS/iam`:

```bash
cd ./app/RasCaaS/iam

aws iam put-role-policy \
  --role-name YOUR_EKS_CLUSTER-lb-controller-role \
  --policy-name rascaas-lbc-set-rule-priorities \
  --policy-document file://policy-lbc-set-rule-priorities.json \
  --profile YOUR_AWS_PROFILE
```

See [`../../../iam/README.md`](../../../iam/README.md) and [`../../../iam/policy-lbc-set-rule-priorities.json`](../../../iam/policy-lbc-set-rule-priorities.json).
