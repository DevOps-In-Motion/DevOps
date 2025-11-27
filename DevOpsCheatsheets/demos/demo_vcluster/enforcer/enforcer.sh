# Set your OKTA credentials
# Example:
export OKTA_ORG_URL="your-token-endpoint-url" # example: kubiya.okta.com
export OKTA_CLIENT_ID="your-client-id"
export OKTA_PRIVATE_KEY_PATH="/path/to/your/private.pem"
export OPAL_POLICY_REPO_URL="https://YOUR/REPO/HERE.git"
export OPAL_POLICY_REPO_MAIN_BRANCH="YOUR_BRANCH" # example: main


# Kubiya Demo
export OKTA_ORG_URL="kubiya.okta.com"
export OKTA_CLIENT_ID="0oaln0xch8xYaTT2B697"
export OKTA_PRIVATE_KEY_PATH="/Users/deon/githubRepos/kubiya/certs/private.pem"
export OPAL_POLICY_REPO_URL="https://github.com/degrasse-python/kubiya-teammate-tools/blob/main/demo-env.repo" # TODO: change this to your repo - private repos don't work
export OPAL_POLICY_REPO_MAIN_BRANCH="main"


# Base64 encode the values
export OKTA_TOKEN_ENDPOINT_B64=$(echo -n "https://$OKTA_ORG_URL/oauth2/v1/token" | base64)
export OKTA_BASE_URL_B64=$(echo -n "https://$OKTA_ORG_URL" | base64)
export OKTA_CLIENT_ID_B64=$(echo -n "$OKTA_CLIENT_ID" | base64)
export PRIVATE_KEY_B64=$(cat "$OKTA_PRIVATE_KEY_PATH" | base64)
export OPAL_POLICY_REPO_URL_B64=$(echo -n "$OPAL_POLICY_REPO_URL" | base64)
export OPAL_POLICY_REPO_MAIN_BRANCH_B64=$(echo -n "$OPAL_POLICY_REPO_MAIN_BRANCH" | base64)

# Check if variables are set correctly
echo "Checking environment variables..."
echo "OKTA_TOKEN_ENDPOINT_B64: ${OKTA_TOKEN_ENDPOINT_B64:0:10}..."
echo "OKTA_CLIENT_ID_B64: ${OKTA_CLIENT_ID_B64:0:10}..."
echo "PRIVATE_KEY_B64: ${PRIVATE_KEY_B64:0:10}..."

vcluster connect se-jit-deon \
  --namespace vcluster-se-jit-deon


kubectl apply -f enforcer.yaml
kubectl apply -f secret.yaml


# Check if pods are running
kubectl get pods -n kubiya

# Check if service is created
kubectl get svc -n kubiya

# Check secrets (without revealing values)
kubectl get secrets -n kubiya

kubectl patch deployment tool-manager -n kubiya --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "KUBIYA_AUTH_SERVER_URL",
      "value": "http://enforcer.kubiya:5001"
    }
  }
]'


kubectl rollout restart deployment tool-manager -n kubiya


#!/bin/bash

# Unset all OKTA and OPAL related environment variables
unset OKTA_ORG_URL
unset OKTA_TOKEN_ENDPOINT_B64
unset OKTA_BASE_URL_B64
unset OKTA_CLIENT_ID_B64
unset PRIVATE_KEY_B64
unset OPAL_POLICY_REPO_URL_B64
unset OPAL_POLICY_REPO_MAIN_BRANCH_B64

# Print confirmation
echo "Environment variables have been unset:"
echo "- OKTA_ORG_URL"
echo "- OKTA_TOKEN_ENDPOINT_B64"
echo "- OKTA_BASE_URL_B64"
echo "- OKTA_CLIENT_ID"
echo "- OKTA_CLIENT_ID_B64"
echo "- OKTA_PRIVATE_KEY_PATH"
echo "- PRIVATE_KEY_B64"
echo "- OPAL_POLICY_REPO_URL"
echo "- OPAL_POLICY_REPO_URL_B64"
echo "- OPAL_POLICY_REPO_MAIN_BRANCH"
echo "- OPAL_POLICY_REPO_MAIN_BRANCH_B64"

# Verify cleanup
if [ -z "$OKTA_ORG_URL" ] && [ -z "$OKTA_TOKEN_ENDPOINT_B64" ] && [ -z "$OKTA_BASE_URL_B64" ]; then
    echo "Cleanup completed successfully."
else
    echo "Warning: Some variables may still be set. Please check your environment."
fi