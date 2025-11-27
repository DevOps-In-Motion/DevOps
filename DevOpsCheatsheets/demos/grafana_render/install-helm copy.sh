
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# open source load balancer
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

kubectl create namespace monitoring
kubectl create namespace ingress-nginx

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

helm upgrade --install ingress-nginx oci://ghcr.io/nginxinc/charts/nginx-ingress \
  --version 1.4.0 \
  -n ingress-nginx \
  --set controller.metrics.enabled=true \
  --set-string controller.podAnnotations."prometheus\.io/scrape"="true" \
  --set-string controller.podAnnotations."prometheus\.io/port"="9113" \
  --values values-nginx.yaml













helm upgrade nginx-ingress ingress-nginx/ingress-nginx \
  --install \
  --set controller.publishService.enabled=true \
  --values values-nginx.yaml 
  
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --install \
  -n ingress-nginx --create-namespace \
  --set controller.metrics.enabled=true \
  --set-string controller.podAnnotations."prometheus\.io/scrape"="true" \
  --set-string controller.podAnnotations."prometheus\.io/port"="10254"

# check service
helm upgrade --install prometheus prometheus-community/prometheus 

# install prometheus stack complete


LATEST=$(curl -s https://api.github.com/repos/prometheus-operator/prometheus-operator/releases/latest | jq -cr .tag_name)
curl https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/$LATEST/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml | kubectl create -f -


helm install grafana grafana/grafana --namespace monitoring \
  --values grafana-values.yaml

export GRAFANA_IP=$(kubectl get svc --namespace monitoring grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

helm uninstall nginx-ingress-staging \
  --namespace nginx-ingress-staging


helm uninstall prometheus-2 prometheus-community/kube-prometheus-stack \
  -n monitoring-staging

helm uninstall grafana grafana/grafana --namespace monitoring

helm uninstall prometheus -n monitoring

{parsed_url.scheme}://{parsed_url.netloc}/render/d-solo/{dashboard_uid}/{dashboard_slug}?orgId={org_id}&from=now-1h&to=now&panelId={panel_id}&width=1000&height=500
