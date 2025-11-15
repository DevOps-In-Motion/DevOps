# Example usage:
sed -e "s/\${TENANT_NAME}/tenant1/g" namespace.yaml | kubectl apply -f -
sed -e "s/\${TENANT_NAME}/tenant1/g" rbac.yaml | kubectl apply -f -
sed -e "s/\${TENANT_NAME}/tenant1/g" network-policy.yaml | kubectl apply -f -