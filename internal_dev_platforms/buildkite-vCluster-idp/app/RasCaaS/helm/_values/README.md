# RaSCaaS Helm install values

Overlays for `helm upgrade --install` (passed with `-f` after chart defaults in `rascaas/values.yaml`).

| File | Environment |
|------|-------------|
| [`qa-install-values.yaml`](qa-install-values.yaml) | QA — `https://rascaas.qa.kovr.ai`, ECR `650251729525`, Cognito `qa-kovr-pool` |

## QA install

```bash
cd platform-testing/RasCaaS

# Gateway + secrets first (see helm/_crds/gateway/README.md)
kubectl apply -f helm/_crds/gateway/rascaas-gateway-base.yaml
# Edit IAM cert in helm/_crds/gateway/rascaas-gateway-https.qa.yaml, then apply it.

helm dependency update ./helm/rascaas
helm upgrade --install rascaas ./helm/rascaas -n rascaas \
  -f helm/_values/qa-install-values.yaml
```

Cognito client ID and `plain-secrets.yaml`: see [RasCaaS/README.md](../../README.md) § OIDC / oauth2-proxy (EKS).

Cluster prerequisites: [`../_crds/README.md`](../_crds/README.md)
