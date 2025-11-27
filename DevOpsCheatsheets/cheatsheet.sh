# login to azure
az login
#Use the following commands to log in to Azure and access cluster.
az account set --subscription "Databricks Azure Sponsorship"
# Obtain AKS creds:
az aks get-credentials --admin --name kubiya-staging-swedencentral  --resource-group app-staging

# connect to vcluster
vcluster connect vcluster-deon -n vcluster-deon
# dry run 



kubectl apply -f https://api.kubiya.ai/api/v3/runners/helm/850b4cfa14c8a7b24882441c8767228405fbbf8a.yaml --dry-run -o yaml > runner-stack.yaml

