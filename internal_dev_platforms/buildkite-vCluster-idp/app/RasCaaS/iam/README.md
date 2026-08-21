# RaSCaaS IAM (QA — account `YOUR_AWS_ACCOUNT_ID`, region `us-west-2`)

Canonical policy/trust JSON for IRSA and GitHub Actions ECR access. Replace `OIDC_PROVIDER_ID` in trust files before create (see below).

## Files

| File | Attach to | Purpose |
|------|-----------|---------|
| [`policy-platform-rascaas.json`](policy-platform-rascaas.json) | Role `platform-rascaas` | CSI: `GetSecretValue` / `DescribeSecret` on SM `rascaas-secrets` |
| [`trust-platform-rascaas.json`](trust-platform-rascaas.json) | Same role (assume-role policy) | IRSA for `rascaas-sa` + `oauth2proxy-sa` |
| [`policy-lbc-set-rule-priorities.json`](policy-lbc-set-rule-priorities.json) | Role `YOUR_EKS_CLUSTER-lb-controller-role` (inline) | Unconditional `SetRulePriorities` / rule CRUD — fixes Gateway HTTPRoute reconciles when listener rules lack `elbv2.k8s.aws/cluster` tag |
| [`policy-rascaas-uat-temp-ecr-cleanup.json`](policy-rascaas-uat-temp-ecr-cleanup.json) | Role `rascaas-uat-temp-ecr-cleanup` | CronJob: describe + delete images in `uat-temp` only |
| [`trust-rascaas-uat-temp-ecr-cleanup.json`](trust-rascaas-uat-temp-ecr-cleanup.json) | Same role (assume-role policy) | IRSA for SA `rascaas` / `rascaas-uat-temp-ecr-cleanup` |
| [`policy-gha-rascaas-ecr-push.json`](policy-gha-rascaas-ecr-push.json) | `GithubBackendDeployRole` (`AWS_DEPLOY_ROLE_ARN`) | Create/push `uat-temp`, `rascaas`, `rascaas-uat-ecr-cleanup` |

GitHub secret: `AWS_DEPLOY_ROLE_ARN=arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/GithubBackendDeployRole`

## Create CSI secrets role (`platform-rascaas`)

Trust JSON already has the QA cluster OIDC id. From this directory:

```bash
export AWS_PROFILE=YOUR_AWS_PROFILE

aws iam create-role \
  --role-name platform-rascaas \
  --assume-role-policy-document file://trust-platform-rascaas.json

aws iam put-role-policy \
  --role-name platform-rascaas \
  --policy-name platform-rascaas-secrets \
  --policy-document file://policy-platform-rascaas.json
```

Then annotate SAs: `kubectl apply -f ../helm/_crds/service-accounts/`

## Fix LBC `SetRulePriorities` AccessDenied (QA Gateway ALB)

Symptom: after changing RaSCaaS `HTTPRoute`s, ALB still has **stale** path rules (e.g. `/api/repos` → FastAPI) while Helm/Kubernetes show the correct routes. Gateway events:

`AccessDenied: … elasticloadbalancing:SetRulePriorities on … listener-rule/…`

Cause: managed policy `YOUR_EKS_CLUSTER-lb-controller-policy` allows `SetRulePriorities` only when `aws:ResourceTag/elbv2.k8s.aws/cluster` is present. Listener **rules** often lack that tag → LBC cannot reorder/delete rules.

Apply additive inline policy (no tag condition), matching AWS LBC IAM docs:

```bash
cd ./app/RasCaaS/iam
export AWS_PROFILE=YOUR_AWS_PROFILE

aws iam put-role-policy \
  --role-name YOUR_EKS_CLUSTER-lb-controller-role \
  --policy-name rascaas-lbc-set-rule-priorities \
  --policy-document file://policy-lbc-set-rule-priorities.json

kubectl rollout restart deployment -n kube-system aws-load-balancer-controller
```

If rules are already stuck, delete the stale `/api/repos|/api/branches|/api/trigger` listener rules (see [`../helm/_crds/gateway/README.md`](../helm/_crds/gateway/README.md)), then let LBC reconcile.

Also confirm **`/api/runner` + `/api/runner/*` → FastAPI** exists with priority **before** catch-all `/*`. Without it, runner callbacks never reach FastAPI (Failed tab / live logs). Manual `create-rule`: same gateway README § Required ALB listener rules.

## Resolve OIDC provider ID

```bash
aws eks describe-cluster --name YOUR_EKS_CLUSTER --region us-west-2 \
  --query 'cluster.identity.oidc.issuer' --output text
# → https://oidc.eks.us-west-2.amazonaws.com/id/<OIDC_PROVIDER_ID>
```

Substitute that ID into `trust-rascaas-uat-temp-ecr-cleanup.json` (three places).

## Create cleanup role (example)

```bash
# After substituting OIDC_PROVIDER_ID:
aws iam create-role \
  --role-name rascaas-uat-temp-ecr-cleanup \
  --assume-role-policy-document file://trust-rascaas-uat-temp-ecr-cleanup.json

aws iam put-role-policy \
  --role-name rascaas-uat-temp-ecr-cleanup \
  --policy-name rascaas-uat-temp-ecr-cleanup \
  --policy-document file://policy-rascaas-uat-temp-ecr-cleanup.json
```

Helm already expects: `arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/rascaas-uat-temp-ecr-cleanup`  
(SA name when release is `rascaas`: `rascaas-uat-temp-ecr-cleanup`.)

## Attach GHA push policy

```bash
aws iam put-role-policy \
  --role-name GithubBackendDeployRole \
  --policy-name rascaas-gha-ecr-push \
  --policy-document file://policy-gha-rascaas-ecr-push.json
```

Do **not** put ECR delete on this role unless you want GHA able to GC as well.
