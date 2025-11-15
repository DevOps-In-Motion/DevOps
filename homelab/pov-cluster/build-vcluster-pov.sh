### ----- Cluster Setup ----- ###
az aks get-credentials --admin --name kubiya-staging-swedencentral  --resource-group app-staging
vcluster upgrade
vcluster create se-povs-deontesting

vcluster connect se-povs \
  --namespace vcluster-se-povs

vcluster connect se-povs-deontesting \
  --namespace vcluster-se-povs-deontesting


### ----- Service Account ----- ###
kubectl create clusterrolebinding kubiya-service-account-access \
  --clusterrole=cluster-admin \
  --serviceaccount=kubiya:kubiya-service-account

### ----- Git Deploy Key ----- ###
# Generate ssh key
ssh-keygen -t ed25519 -C "adsaunde@protonmail.com" -f ./kubiya_deploy_key -N ""
# Print public key to add deploy key in git repo probider
cat ./kubiya_deploy_key.pub

export GIT_DEPLOY_KEY=$(cat ./kubiya_deploy_key)
export GIT_DEPLOY_KEY_BS64=$(echo -n "$GIT_DEPLOY_KEY" | base64)
echo "GIT_DEPLOY_KEY is set: $([[ -n "$GIT_DEPLOY_KEY" ]] && echo "✓" || echo "✗")"

kubectl create secret generic git-deploy-key \
  --from-literal=gh-token="$GIT_DEPLOY_KEY_BS64" \
  -n kubiya


kubectl delete secret github-token -n kubiya
kubectl create secret generic github-token \
  --from-literal=gh-token="$GIT_DEPLOY_KEY_BS64" \
  -n kubiya


kubectl patch deployment tool-manager -n kubiya \
  --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/env",
      "value": [
        {
          "name": "TOOLS_GH_TOKEN",
          "valueFrom": {
            "secretKeyRef": {
              "name": "github-token",
              "key": "gh-token"
            }
          }
        }
      ]
    },
    {
      "op": "add",
      "path": "/spec/template/spec/containers/1/env",
      "value": [
        {
          "name": "TOOLS_GH_TOKEN",
          "valueFrom": {
            "secretKeyRef": {
              "name": "github-token",
              "key": "gh-token"
            }
          }
        }
      ]
    }
  ]'




### ----- Maintenance ----- ###
vcluster delete se-povs




