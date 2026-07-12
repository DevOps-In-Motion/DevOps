# RaSCaaS Gateway (AWS LBC + Gateway API)

## Files

| File | When to apply |
|------|----------------|
| [`rascaas-gateway-base.yaml`](rascaas-gateway-base.yaml) | First — HTTP :80, TargetGroupConfiguration, LoadBalancerConfiguration |
| [`rascaas-gateway-https.qa.yaml`](rascaas-gateway-https.qa.yaml) | QA — HTTPS :443, hostname `rascaas.qa.kovr.ai` (edit IAM cert ARN first) |
| [`rascaas-gateway-https.template.yaml`](rascaas-gateway-https.template.yaml) | Other envs — `sed` placeholders `__RASCAAS_GATEWAY_HOSTNAME__`, `__IAM_SERVER_CERT_ARN__` |

## QA apply order

```bash
cd platform-testing/RasCaaS

# After Gateway API CRDs + namespace rascaas (see ../README.md)

kubectl apply -f helm/_crds/gateway/rascaas-gateway-base.yaml

# List IAM server certs in QA account, pick one that includes rascaas.qa.kovr.ai
export AWS_PROFILE=qa-kovr
aws iam list-server-certificates --query 'ServerCertificateMetadataList[*].[ServerCertificateName,Arn]' --output table

# Edit rascaas-gateway-https.qa.yaml: set defaultCertificate to that ARN, then:
kubectl apply -f helm/_crds/gateway/rascaas-gateway-https.qa.yaml

kubectl get gateway rascaas-gateway -n rascaas -w
```

Point **DNS** `rascaas.qa.kovr.ai` at the ALB address in `status.addresses`.

## Must match Helm (`helm/_values/qa-install-values.yaml`)

| Layer | Field |
|-------|--------|
| Gateway HTTPS listener | `hostname: rascaas.qa.kovr.ai` (in `rascaas-gateway-https.qa.yaml`) |
| HTTPRoutes | `gateway.hostname: rascaas.qa.kovr.ai` |
| oauth2-proxy / FastAPI | `APP_BASE_URL`, `redirectUrl` |
| Cognito app client | Allowed callback `https://rascaas.qa.kovr.ai/oauth2/callback` |

Then install the chart:

```bash
helm upgrade --install rascaas ./helm/rascaas -n rascaas -f helm/_values/qa-install-values.yaml
```
