# Install KEDA operator
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml

# Verify installation
kubectl get pods -n keda