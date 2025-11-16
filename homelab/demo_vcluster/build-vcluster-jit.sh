
az aks get-credentials --admin --name kubiya-staging-swedencentral  --resource-group app-staging
vcluster upgrade
vcluster create se-jit-deon

vcluster connect se-jit-deon \
  --namespace vcluster-se-jit-deon

vcluster delete sa-prod




