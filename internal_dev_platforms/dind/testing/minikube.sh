# Start minikube with 2 CPUs, 4GB RAM, and 5GB of disk storage
minikube start --cpus=2 --memory=4096 --disk-size=5g
# enable ingress
minikube addons enable ingress
# minikube addons enable volumesnapshots
# minikube addons enable csi-hostpath-driver

k apply -f test-wiki-stack.yaml

# port 
kubectl port-forward service/wiki-api-service 8080:8080 &

kubectl port-forward svc/wiki-api-service 8080:8080 & sleep 3 && curl -s -w "\nHTTP %{http_code}\n" http://localhost:8080/health


kubectl port-forward -n default svc/wiki-api-service 8080:8080 &>/dev/null &

# testing full helm
kubectl port-forward -n monitoring svc/prometheus-operator-prometheus 9090:9090 &>/dev/null &
kubectl port-forward -n monitoring svc/prometheus-operator-grafana 3000:80 &>/dev/null &
kubectl port-forward -n wiki-api svc/wiki-api-service 8080:8080 &>/dev/null &


### --- Docker --- ###
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/i3h9f2j0
cd ../wiki-service
# docker build -t wiki-backend:latest .
# docker tag wiki-backend:latest 588738600522.dkr.ecr.us-east-1.amazonaws.com/wiki-backend:latest
docker build -t demos/wiki-backend .
docker tag demos/wiki-backend:latest public.ecr.aws/i3h9f2j0/demos/wiki-backend:latest
docker push public.ecr.aws/i3h9f2j0/demos/wiki-backend:latest