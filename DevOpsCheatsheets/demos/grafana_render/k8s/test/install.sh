# https://kubernetes.github.io/ingress-nginx/user-guide/monitoring/


helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# open source load balancer
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add datree-webhook https://datreeio.github.io/admission-webhook-datree
helm repo update

helm upgrade nginx-ingress ingress-nginx/ingress-nginx \
  --install \
  -n ingress-nginx --create-namespace \
  --set controller.metrics.enabled=true \
  --set-string controller.podAnnotations."prometheus\.io/scrape"="true" \
  --set-string controller.podAnnotations."prometheus\.io/port"="10254"


kubectl apply --kustomize github.com/kubernetes/ingress-nginx/deploy/prometheus/
kubectl apply --kustomize github.com/kubernetes/ingress-nginx/deploy/grafana/


kubectl port-forward  -n ingress-nginx svc/prometheus-server 9090:9090 &
kubectl port-forward  -n ingress-nginx svc/grafana  3000:80 &


kubectl get nodes --selector=kubernetes.io/role!=master -o jsonpath={.items[*].status.addresses[?\(@.type==\"InternalIP\"\)].address}