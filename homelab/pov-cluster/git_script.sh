#!/bin/bash


# Function to display usage information
usage() {
    echo "Usage: $0 [options] <GitHub token>"
    echo ""
    echo "Options:"
    echo "  --dry-run      Simulate the actions without applying any changes"
    echo "  --help         Display this help message"
    exit 1
}	


# Parse arguments
dry_run_flag=""
token=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run) dry_run_flag="--dry-run=client" ;;
        --help) usage ;;
        *) token=$1 ;;
    esac
    shift
done


# If no token was passed as an argument, prompt the user
if [ -z "$token" ]; then
    echo "Enter your GitHub token:"
    read -s token
fi


# Create or update the Kubernetes secret
kubectl delete secret github-token -n kubiya $dry_run_flag &>/dev/null
kubectl create secret generic github-token -n kubiya --from-literal=gh-token=$token $dry_run_flag


# Define the patch content
patch=$(cat <<EOF
spec:
  template:
    spec:
      containers:
        - name: tool-manager
          env:
            - name: TOOLS_GH_TOKEN
              valueFrom:
                secretKeyRef:
                  name: github-token
                  key: gh-token
        - name: kubiya-sdk-server
          env:
            - name: TOOLS_GH_TOKEN
              valueFrom:
                secretKeyRef:
                  name: github-token
                  key: gh-token
EOF
)


# Apply the patch to the deployment
kubectl patch deployment -n kubiya tool-manager --patch "$patch" $dry_run_flag


# Optionally restart the deployment if not in dry-run mode
if [ -z "$dry_run_flag" ]; then
    kubectl rollout restart deployment -n kubiya tool-manager
fi


