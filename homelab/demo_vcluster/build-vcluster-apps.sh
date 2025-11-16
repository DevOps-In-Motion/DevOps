
az aks get-credentials --admin --name kubiya-staging-swedencentral  --resource-group app-staging
vcluster upgrade
vcluster create sa-prod

vcluster connect sa-prod \
  --namespace vcluster-sa-prod

vcluster delete sa-prod

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

argocd admin initial-password -n argocd

# patch the configmap to add server.insecure=true
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'

# restart the argocd-server deployment
kubectl rollout restart deployment argocd-server -n argocd

# create the ingress
kubectl apply -f k8s/argocd/argo-ingress-https.yaml

# https://localhost:8080
kubectl port-forward svc/argocd-server -n argocd 8080:443
