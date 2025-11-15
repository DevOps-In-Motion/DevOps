# quick install for octopus on minikube
minikube start --cpus 4 --memory 8192 --disk-size 20g
minikube addons enable ingress
minikube addons enable metrics-server

kubectl create namespace octopus
kubectl create namespace ingress-nginx
kubectl create namespace postgresql-prod
# kubectl create namespace ingress
helm repo add jetstack https://charts.jetstack.io --force-update
helm pull oci://registry-1.docker.io/octopusdeploy/octopusdeploy-helm
helm repo update

minikube tunnel &

helm upgrade -i \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.5 \
  --set installCRDs=true

kubectl apply -f cert/clusterissuer.yml
kubectl apply -f cert/inmotion-cert.yml

# ingress required for helm install
helm upgrade -i ingress-nginx oci://ghcr.io/nginxinc/charts/nginx-ingress \
  --values nginx-values.yaml \
  -n ingress-nginx \
  --version 1.2.1
minikube service ingress-nginx-nginx-ingress-controller  -n ingress-nginx  
kubectl get svc -n ingress-nginx

# minikube addons enable ingress 
# kubectl apply -f nginx-values.yaml -n ingress-nginx
kubectl get ingress -n ingress-nginx


openssl rand -base64 16 > octopus-master-key

# helm install mssql-latest-deploy . --set ACCEPT_EULA.value=Y --set MSSQL_PID.value=Developer
helm upgrade -i postgresql-prod oci://registry-1.docker.io/bitnamicharts/postgresql \
  --namespace postgresql-prod

minikube service postgresql-prod  -n postgresql-prod  

export POSTGRES_PASSWORD=$(kubectl get secret --namespace postgresql-prod postgresql-prod -o jsonpath="{.data.postgres-password}" | base64 -d)
export POSTGRES_USER=$(kubectl get secret --namespace postgresql-prod postgresql-prod -o jsonpath="{.data.postgres-username}" | base64 -d)
kubectl port-forward --namespace postgresql-prod svc/postgresql-prod 5432:5432 &
    PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5432 &

kubectl get all

helm upgrade --install octopus-deploy oci://registry-1.docker.io/octopusdeploy/octopusdeploy-helm  \
    --values octopus-values.yaml \
    -n octopus \
    --debug

kubectl -n octopus get secret  octopus-deploy-secrets  -o jsonpath="{.data.password}" | base64 -d ; echo
