# get python app from internet
curl -fsSL https://raw.github.com/

# creating a container (e.g., with Docker), 
# Docker image
docker build -t "5thcinema/go-backend-services:k8s-interview" .
# docker tag 5thcinema/go-backend-services 5thcinema/go-backend-services:connectrpc-climatesrv

docker push 5thcinema/go-backend-services:k8s-interview

docker save 5thcinema/go-backend-services:k8s-interview | gzip > k8s-interview.tar.gz

docker builder prune --all


# pull image
docker pull <image>

# and then deploying it to a minikube cluster.

# quick install for octopus on minikube
minikube start --cpus 4 --memory 8192 --disk-size 20g
minikube addons enable ingress
minikube addons enable metrics-server
