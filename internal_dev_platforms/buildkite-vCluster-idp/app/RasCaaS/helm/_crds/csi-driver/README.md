# RaSCaaS — SecretProviderClass (application stack)

Apply after secrets-store CSI + ASCP are installed (`helm-charts/external/test/csi`).

| File | SPC name | SM secret | Synced K8s Secret | Consumed by |
|------|----------|-----------|-------------------|-------------|
| [`secretproviderclass-rascaas-fastapi.qa.yaml`](secretproviderclass-rascaas-fastapi.qa.yaml) | `rascaas-fastapi-secrets-provider` | `rascaas-secrets` | `fastapi-secrets` (`github-private-key`, `runner-callback-token`) | FastAPI (`rascaas-sa`) |
| [`secretproviderclass-oauth2proxy.qa.yaml`](secretproviderclass-oauth2proxy.qa.yaml) | `oauth2proxy-secrets-provider` | `rascaas-secrets` | `oauth2proxy-secret` | oauth2-proxy (`oauth2proxy-sa`) |

Both SPCs read the same SM JSON (`rascaas-secrets`); each syncs only the keys its workload needs.

```bash
# From helm/
kubectl apply -f _crds/namespace.yaml
kubectl apply -f _crds/service-accounts/
kubectl apply -f _crds/csi-driver/
```

Helm (`_values/qa-install-values.yaml`): `secrets.mode=csi-driver` plus per-app SPC names.
