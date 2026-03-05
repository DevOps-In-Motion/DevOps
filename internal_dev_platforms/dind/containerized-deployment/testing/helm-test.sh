### ----- Vanilla Install ----- ###
# add repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 
# open source load balancer
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add datree-webhook https://datreeio.github.io/admission-webhook-datree
helm repo update
# install
helm upgrade --install prometheus-operator prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f /Users/deon/githubRepos/interviews/nebula-aurora-assignment/testing/values-prometheus-stack.yaml

# localhost:3000/grafana/d/creation-dashboard-678/creation


kubectl --namespace monitoring get secrets prometheus-operator-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
export POD_NAME=$(kubectl --namespace monitoring get pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=prometheus-operator" -oname)
kubectl --namespace monitoring port-forward $POD_NAME 3000
kubectl get secret --namespace monitoring -l app.kubernetes.io/component=admin-secret -o jsonpath="{.items[0].data.admin-password}" | base64 --decode ; echo


kubectl port-forward -n monitoring svc/prometheus-operator-prometheus 9090:9090 &>/dev/null &
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 &>/dev/null &

# Render with your test values (recommended)
helm template myrelease wiki-chart --debug \
  -f minikube/helm-test-values.yaml 

# test min helm chart  
helm upgrade --install wiki-api ./wiki-chart \
  -f testing/helm-test-values-min.yaml 

# test full helm chart
helm upgrade --install wiki-api ./wiki-chart \
  -n wiki-api --create-namespace \
  -f ./testing/helm-test-values-full.yaml \
  --wait 7m

# testing full helm (Grafana service is <release>-grafana, e.g. wiki-api-grafana)
kubectl port-forward -n monitoring svc/prometheus-operator-prometheus 9090:9090 &>/dev/null &
kubectl port-forward -n monitoring svc/wiki-api-grafana 3000:80 &>/dev/null &
kubectl port-forward -n wiki-api svc/wiki-api-service 8080:8080 &>/dev/null &

# Optional: stop anything on 3000, 9090, 8080 (macOS)
lsof -ti:3000,9090,8080 | xargs kill

# Then run the three port-forwards (Grafana now uses wiki-api-grafana)
kubectl port-forward -n monitoring svc/prometheus-operator-prometheus 9090:9090 &>/dev/null &
kubectl port-forward -n monitoring svc/wiki-api-grafana 3000:80 &>/dev/null &
kubectl port-forward -n wiki-api svc/wiki-api-service 8080:8080 &>/dev/null &



### --- Validation --- ###
# Only render one template (e.g. ingress)
helm template myrelease wiki-chart -f minikube/helm-test-values.yaml -s templates/ingress.yaml --debug

# See the computed values (chart defaults + your overrides)
helm template myrelease wiki-chart -f minikube/helm-test-values.yaml --debug --show-only templates/ingress.yaml 2>/dev/null

# Validate that the chart has no missing deps (if you use subcharts)
cd wiki-chart && helm dependency update && cd ..
helm template myrelease wiki-chart -f minikube/helm-test-values.yaml --debug

# check the ingress
helm template wiki wiki-chart -f minikube/helm-test-values.yaml -s templates/ingress.yaml