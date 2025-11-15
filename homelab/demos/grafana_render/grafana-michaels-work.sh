
# get the right k8s context
az aks get-credentials --admin --name kubiya-staging-swedencentral  --resource-group app-staging

# connect to vcluster
# everything lives in the monitoring ns
k get pods -n monitoring

# port forward to get to all svc
# 
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 &


# check localhost:3000
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:3000 &
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
kubectl port-forward -n monitoring svc/grafana-renderer-svc 8081:8081 &

# the alert used 
kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo


{parsed_url.scheme}://{parsed_url.netloc}/render/d-solo/{dashboard_uid}/{dashboard_slug}?orgId={org_id}&from=now-1h&to=now&panelId={panel_id}&width=1000&height=500

http://grafana.demos.kubiya.ai/render/d/4DFTt9Wnk/nginx-performance?orgId=1