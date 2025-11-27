
DNS_LABEL=demos.kubiya.ai

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


### ----- Install Prometheus Stack and Nginx ----- ###

# prometheus
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.replicas=2 \
  --set alertmanager.alertmanagerSpec.replicas=2 \
  --set grafana.replicas=2 \
  --set prometheus.prometheusSpec.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight=100 \
  --set prometheus.prometheusSpec.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchExpressions[0].key="app" \
  --set prometheus.prometheusSpec.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchExpressions[0].operator="In" \
  --set prometheus.prometheusSpec.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchExpressions[0].values[0]="prometheus" \
  --set prometheus.prometheusSpec.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.topologyKey="kubernetes.io/hostname" \
  --set grafana.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight=100 \
  --set grafana.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchExpressions[0].key="app.kubernetes.io/name" \
  --set grafana.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchExpressions[0].operator="In" \
  --set grafana.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchExpressions[0].values[0]="grafana" \
  --set grafana.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.topologyKey="kubernetes.io/hostname"


helm upgrade --install ingress-nginx oci://ghcr.io/nginxinc/charts/nginx-ingress \
  --version 1.4.0 \
  -n ingress-nginx \
  --set controller.metrics.enabled=true \
  --set controller.config.enable-ssl-passthrough=true \
  --set-string controller.podAnnotations."prometheus\.io/scrape"="true" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=demos.kubiya.ai \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --set-string controller.podAnnotations."prometheus\.io/port"="9113" \
  --values values-nginx.yaml

# install cert manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml


# install the CRD scrape for the service monitor
kubectl apply -f grafana_render/prometheus-stack/prometheus.yaml

# install the plugin
kubectl apply -f grafana_render/renderer-deploy.yaml
kubectl apply -f grafana_render/renderer-svc.yaml
kubectl apply -f grafana_render/renderer-ing.yaml

# create the ingress for the pro-stack
kubectl apply -f grafana_render/prometheus-stack/prometheus-stack-ing.yaml


### --- for localhost access if needed
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &

# get the password for the admin
kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo


export GRAFANA_IP=$(kubectl get svc --namespace monitoring grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo


### ----- Uninstall ----- ###

helm uninstall nginx-ingress \
  --namespace nginx-ingress

helm uninstall prometheus-staging prometheus-community/kube-prometheus-stack \
  -n monitoring-staging

helm uninstall grafana grafana/grafana --namespace monitoring

helm uninstall prometheus -n monitoring

{parsed_url.scheme}://{parsed_url.netloc}/render/d-solo/{dashboard_uid}/{dashboard_slug}?orgId={org_id}&from=now-1h&to=now&panelId={panel_id}&width=1000&height=500

# to test enter this into address bar
http://grafana.demos.kubiya.ai/render/d/4DFTt9Wnk/nginx-performance?orgId=1

