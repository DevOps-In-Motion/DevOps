
az aks get-credentials --admin --name kubiya-staging-swedencentral  --resource-group app-staging
vcluster upgrade
vcluster create github-cicd

vcluster connect sa-prod \
  --namespace vcluster-sa-prod

vcluster delete sa-prod




