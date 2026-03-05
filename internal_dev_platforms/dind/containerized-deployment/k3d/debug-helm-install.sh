#!/usr/bin/env bash
# Debug script to run in another terminal while entrypoint.sh is running (e.g. during helm install).
#
# From host (DinD):   ./k3d/debug-helm-install.sh   # finds wiki-k3d-dind container, runs inside, then prints exec command
# From host (socket): export KUBECONFIG=$(k3d kubeconfig write wiki); ./k3d/debug-helm-install.sh
# Inside container:   export KUBECONFIG=$(k3d kubeconfig write wiki); /app/k3d/debug-helm-install.sh
#
# Optional: NAMESPACE=default CLUSTER_NAME=wiki (defaults shown).

set -e

CLUSTER_NAME="${K3D_CLUSTER_NAME:-wiki}"
NAMESPACE="${HELM_NAMESPACE:-default}"

# When run from host: if no cluster visible, find DinD container and re-run this script inside it
if ! command -v k3d &>/dev/null || ! k3d cluster list 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
  # Prefer exact container name (set by test-k3d.sh / README), then image
  WIKI_K3D_CONTAINER=$(docker ps -q --filter "name=^wiki-k3d-dind$" 2>/dev/null | head -1)
  if [[ -z "$WIKI_K3D_CONTAINER" ]]; then
    WIKI_K3D_CONTAINER=$(docker ps -q --filter "ancestor=wiki-k3d-dind" 2>/dev/null | head -1)
  fi
  if [[ -n "$WIKI_K3D_CONTAINER" ]]; then
    export WIKI_K3D_CONTAINER
    echo "DinD container found: $WIKI_K3D_CONTAINER. Running debug inside container..."
    echo ""
    docker exec "$WIKI_K3D_CONTAINER" /app/k3d/debug-helm-install.sh
    echo ""
    echo "To get a shell inside the container: docker exec -it $WIKI_K3D_CONTAINER sh"
    exit 0
  fi
  echo "Cannot reach cluster and no running wiki-k3d-dind container found."
  echo "Start the cluster first: docker run --rm -it --privileged --cgroupns=host -p 8080:8080 -p 8443:8443 -v wiki-data:/data wiki-k3d-dind"
  exit 1
fi

# Use k3d kubeconfig if KUBECONFIG not set (e.g. when running inside the image)
if [[ -z "${KUBECONFIG:-}" ]] && command -v k3d &>/dev/null; then
  export KUBECONFIG="$(k3d kubeconfig write "$CLUSTER_NAME" 2>/dev/null)"
fi

if ! kubectl cluster-info &>/dev/null; then
  echo "Cannot reach cluster. Set KUBECONFIG or run where k3d/kubectl can see cluster $CLUSTER_NAME."
  exit 1
fi

echo "=== Nodes ==="
kubectl get nodes -o wide 2>/dev/null || true

echo ""
echo "=== Pods (namespace: $NAMESPACE) ==="
kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || true

echo ""
echo "=== Recent events (namespace: $NAMESPACE) ==="
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -25

NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -v "Running\|Completed" || true)
if [[ -n "$NOT_READY" ]]; then
  echo ""
  echo "=== Not-ready pods (describe) ==="
  while read -r line; do
    pod=$(echo "$line" | awk '{print $1}')
    [[ -z "$pod" ]] && continue
    echo "--- $pod ---"
    kubectl describe pod "$pod" -n "$NAMESPACE" 2>/dev/null | tail -40
  done <<< "$NOT_READY"
fi

echo ""
echo "=== PVCs (namespace: $NAMESPACE) ==="
kubectl get pvc -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "=== Helm release status ==="
helm list -n "$NAMESPACE" 2>/dev/null || true

# --- Extensive Grafana + Traefik ingress routing debug ---
echo ""
echo "========== GRAFANA & TRAEFIK INGRESS ROUTING DEBUG =========="
echo ""

echo "--- 1. All Ingresses (default + monitoring) ---"
for ns in "$NAMESPACE" monitoring; do
  echo ">>> Ingresses in namespace: $ns"
  kubectl get ingress -n "$ns" -o wide 2>/dev/null || true
  echo ""
done

echo "--- 2. Ingresses associated with Grafana (paths, backends, class) ---"
echo ">>> All namespaces: NAME, CLASS, HOSTS, PATHS, BACKEND:"
kubectl get ingress -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host,PATHS:.spec.rules[*].http.paths[*].path,PATHTYPE:.spec.rules[*].http.paths[*].pathType,BACKEND:.spec.rules[*].http.paths[*].backend.service.name' 2>/dev/null || true
echo ""
echo ">>> describe each Ingress in monitoring (Grafana namespace):"
for ing in $(kubectl get ingress -n monitoring -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo "  --- Ingress: $ing ---"
  kubectl describe ingress -n monitoring "$ing" 2>/dev/null || true
done
echo ""
echo ">>> describe each Ingress in $NAMESPACE (wiki; may have / or /grafana):"
for ing in $(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo "  --- Ingress: $ing ---"
  kubectl describe ingress -n "$NAMESPACE" "$ing" 2>/dev/null || true
done
echo ""
echo ">>> YAML of all Ingresses in monitoring:"
kubectl get ingress -n monitoring -o yaml 2>/dev/null || true
echo ""
echo ">>> YAML of all Ingresses in $NAMESPACE:"
kubectl get ingress -n "$NAMESPACE" -o yaml 2>/dev/null || true

echo "--- 3. Traefik: namespace watch (must include 'monitoring' for Grafana Ingress to be seen) ---"
TRAEFIK_DEPLOY=$(kubectl get deploy -n kube-system -o name 2>/dev/null | grep -i traefik | head -1)
if [[ -n "$TRAEFIK_DEPLOY" ]]; then
  echo ">>> Traefik deployment: $TRAEFIK_DEPLOY"
  kubectl get "$TRAEFIK_DEPLOY" -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | tr ',' '\n' || true
  echo ""
  echo ">>> Full Traefik container args:"
  kubectl get "$TRAEFIK_DEPLOY" -n kube-system -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{.}{"\n"}{end}' 2>/dev/null || true
else
  echo ">>> No Traefik deployment found in kube-system."
fi
echo ""
echo ">>> HelmChartConfig for Traefik (k3d config file injects this to set namespaces):"
kubectl get helmchartconfig -n kube-system 2>/dev/null || true
kubectl get helmchartconfig -n kube-system -o yaml 2>/dev/null || true

echo "--- 4. IngressClass (Traefik should be default or present for className: traefik) ---"
kubectl get ingressclass -o wide 2>/dev/null || true
kubectl get ingressclass -o yaml 2>/dev/null || true

echo "--- 5. Grafana Service & Endpoints in monitoring ---"
kubectl get svc -n monitoring -l 'app.kubernetes.io/name=grafana' -o wide 2>/dev/null || true
kubectl get svc -n monitoring | grep -i grafana || true
echo ">>> Grafana service(s) full YAML:"
kubectl get svc -n monitoring -o yaml 2>/dev/null | grep -A 200 "name: prometheus-operator-grafana\|name:.*grafana" | head -80 || true
echo ">>> Endpoints for Grafana (must have addresses for routing to work):"
kubectl get endpoints -n monitoring | grep -i grafana || true
kubectl get endpoints -n monitoring -o yaml 2>/dev/null | grep -B 5 -A 30 "prometheus-operator-grafana\|grafana" | head -60 || true

echo "--- 6. Helm values affecting Grafana ingress (path, ingress.enabled, ingressClassName) ---"
RELEASE_NAME=$(helm list -n "$NAMESPACE" -q 2>/dev/null | head -1)
if [[ -n "$RELEASE_NAME" ]]; then
  echo ">>> Release: $RELEASE_NAME (prometheus-stack.grafana.ingress and main ingress):"
  helm get values "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 20 'grafana:' | head -35 || true
  helm get values "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null | grep -B 2 -A 15 'ingress:' | head -50 || true
  echo ">>> Full values: ingress section"
  helm get values "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null | sed -n '/^ingress:/,/^[a-z]/p' || true
  echo ">>> Full values: prometheus-stack (grafana.ingress.enabled, path, ingressClassName):"
  helm get values "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null | sed -n '/prometheus-stack:/,/^[a-z]/p' | head -60 || true
else
  echo ">>> No Helm release in $NAMESPACE; skip helm get values."
fi

echo "--- 7. What to check for routing ---"
echo "  - Grafana subchart ingress: if prometheus-stack.grafana.ingress.enabled is true, the subchart may create an Ingress with path: / (root). That conflicts with our chart's Ingress (path: /grafana) on the same host; Traefik may route / to one and /grafana to the other. For /grafana to work: (1) Traefik must watch namespace 'monitoring' (see section 3). (2) Exactly one Ingress should expose path /grafana → prometheus-operator-grafana:80; the Grafana subchart ingress should use path /grafana or be disabled so our wiki-chart ingress-grafana is used. (3) Grafana.ini: server.root_url and serve_from_sub_path must be set for subpath /grafana/."
echo "  - If the subchart creates an Ingress with path: / and ingressClassName: traefik in monitoring, it will take all traffic to host:localhost/ and Grafana at /grafana may 404 unless our chart's Ingress exists and has path /grafana with pathType Prefix."
echo ""

echo "--- 8. Traefik logs (last 30 lines, if available) ---"
TRAEFIK_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$TRAEFIK_POD" ]]; then
  kubectl logs -n kube-system "$TRAEFIK_POD" --tail=30 2>/dev/null || true
else
  echo ">>> No Traefik pod found."
fi

echo ""
echo "========== END GRAFANA & TRAEFIK DEBUG =========="
echo ""

# --- PostgreSQL / metrics pipeline debug (why dashboard has no data) ---
echo "========== POSTGRESQL / METRICS PIPELINE DEBUG =========="
echo ""

echo "--- 1. ServiceMonitors (default + monitoring) ---"
for ns in "$NAMESPACE" monitoring; do
  echo ">>> ServiceMonitors in namespace: $ns"
  kubectl get servicemonitor -n "$ns" -o wide 2>/dev/null || true
  count=$(kubectl get servicemonitor -n "$ns" --no-headers 2>/dev/null | wc -l)
  if [[ "${count:-0}" -gt 0 ]]; then
    for sm in $(kubectl get servicemonitor -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
      echo "  --- ServiceMonitor: $sm (namespace: $ns) ---"
      kubectl get servicemonitor -n "$ns" "$sm" -o jsonpath='  selector: {.spec.selector}' 2>/dev/null; echo ""
      kubectl get servicemonitor -n "$ns" "$sm" -o jsonpath='  namespaceSelector: {.spec.namespaceSelector}' 2>/dev/null; echo ""
      kubectl get servicemonitor -n "$ns" "$sm" -o jsonpath='  endpoints: {.spec.endpoints}' 2>/dev/null; echo ""
    done
  fi
  echo ""
done
echo ">>> YAML of ServiceMonitors in $NAMESPACE (wiki backend scrape config):"
kubectl get servicemonitor -n "$NAMESPACE" -o yaml 2>/dev/null || true

echo "--- 2. Wiki backend Service (must match ServiceMonitor selector + have port name 'http') ---"
WIKI_SVC=$(kubectl get svc -n "$NAMESPACE" -o name 2>/dev/null | grep -E 'wiki|backend' | head -1)
if [[ -n "$WIKI_SVC" ]]; then
  echo ">>> Service: $WIKI_SVC"
  kubectl get "$WIKI_SVC" -n "$NAMESPACE" -o wide 2>/dev/null || true
  echo ">>> Labels (ServiceMonitor selector must match these):"
  kubectl get "$WIKI_SVC" -n "$NAMESPACE" -o jsonpath='{.metadata.labels}' 2>/dev/null | tr ',' '\n' || true
  echo ""
  echo ">>> Ports (ServiceMonitor expects port name 'http'):"
  kubectl get "$WIKI_SVC" -n "$NAMESPACE" -o jsonpath='{range .spec.ports[*]}{.name}: {.port}{"\n"}{end}' 2>/dev/null || true
else
  echo ">>> No wiki/backend Service found in $NAMESPACE."
fi

echo "--- 3. Prometheus: which namespaces it watches for ServiceMonitors ---"
PROM_CRD=$(kubectl get prometheus -n monitoring -o name 2>/dev/null | head -1)
if [[ -n "$PROM_CRD" ]]; then
  echo ">>> Prometheus CR: $PROM_CRD"
  kubectl get "$PROM_CRD" -n monitoring -o jsonpath='serviceMonitorNamespaceSelector: {.spec.serviceMonitorNamespaceSelector}' 2>/dev/null; echo ""
  kubectl get "$PROM_CRD" -n monitoring -o jsonpath='serviceMonitorSelector: {.spec.serviceMonitorSelector}' 2>/dev/null; echo ""
  echo ">>> Full prometheusSpec (serviceMonitor*):"
  kubectl get "$PROM_CRD" -n monitoring -o yaml 2>/dev/null | grep -A 2 -E 'serviceMonitorSelector|serviceMonitorNamespaceSelector' || true
else
  echo ">>> No Prometheus CR found in monitoring namespace."
fi

echo "--- 4. /metrics reachability from inside cluster ---"
WIKI_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
SVC_NAME=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$WIKI_POD" ]] && [[ -n "$SVC_NAME" ]]; then
  echo ">>> Curl /metrics from wiki backend pod (same namespace, first container):"
  kubectl exec -n "$NAMESPACE" "$WIKI_POD" -- wget -qO- "http://127.0.0.1:8080/metrics" 2>/dev/null | head -30 || kubectl exec -n "$NAMESPACE" "$WIKI_POD" -- curl -s "http://127.0.0.1:8080/metrics" 2>/dev/null | head -30 || echo "  (wget/curl failed; try: kubectl exec -n $NAMESPACE $WIKI_POD -c <container> -- curl -s http://127.0.0.1:8080/metrics)"
  echo ""
  echo ">>> From monitoring namespace (Prometheus scrapes from here):"
  PROM_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -n "$PROM_POD" ]]; then
    kubectl exec -n monitoring "$PROM_POD" -c prometheus -- wget -qO- "http://${SVC_NAME}.${NAMESPACE}.svc.cluster.local:8080/metrics" 2>/dev/null | head -20 || echo "  (wget from Prometheus pod failed; check network policy / DNS)"
  else
    echo "  (no Prometheus pod found to test from)"
  fi
else
  echo ">>> No wiki backend pod or service found (labels: app.kubernetes.io/name=backend)."
fi

echo "--- 5. Prometheus scrape targets (wiki job) ---"
PROM_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$PROM_POD" ]]; then
  echo ">>> Targets from Prometheus API (filter backend/wiki):"
  kubectl exec -n monitoring "$PROM_POD" -c prometheus -- wget -qO- "http://127.0.0.1:9090/api/v1/targets" 2>/dev/null | grep -o '"job":"[^"]*"' | sort -u || true
  echo ">>> Full targets JSON (scrapeUrl, health):"
  kubectl exec -n monitoring "$PROM_POD" -c prometheus -- wget -qO- "http://127.0.0.1:9090/api/v1/targets" 2>/dev/null | grep -E 'scrapeUrl|health|job' | head -40 || true
else
  echo ">>> No Prometheus pod; run: kubectl port-forward -n monitoring svc/prometheus-operator-prometheus 9090:9090 && curl -s localhost:9090/api/v1/targets | jq ."
fi

echo "--- 6. What to check for PostgreSQL dashboard / metrics ---"
echo "  - ServiceMonitor.spec.namespaceSelector.matchNames must include the namespace where the wiki backend Service runs ($NAMESPACE). If it says 'wiki-api' and release is in 'default', Prometheus will not discover the target."
echo "  - ServiceMonitor.spec.selector must match the wiki Service labels (e.g. app.kubernetes.io/name: backend)."
echo "  - Service must have a port named 'http' (ServiceMonitor endpoints.port: http)."
echo "  - Prometheus must watch the namespace where the ServiceMonitor lives (serviceMonitorNamespaceSelector) and select this ServiceMonitor (serviceMonitorSelector / release label)."
echo "  - Dashboard datasource must be Prometheus; panels use metrics from the wiki backend (e.g. creation_*). If targets are up but dashboard empty, check metric names in the dashboard JSON."
echo ""

echo "========== END POSTGRESQL / METRICS DEBUG =========="
echo ""
echo "--- To get logs of a failing pod: kubectl logs <pod> -n $NAMESPACE [-c <container>] ---"
