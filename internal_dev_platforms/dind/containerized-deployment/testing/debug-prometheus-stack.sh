#!/usr/bin/env bash
# Debug the existing deployment: vanilla wiki (test-wiki-stack.yaml) + Helm (values-prometheus-stack.yaml).
# Checks cluster state and, if needed, what Helm would render.
#
# Prerequisites:
#   - test-wiki-stack.yaml applied (wiki-api Deployment, wiki-api-service in default)
#   - Helm install of kube-prometheus-stack using testing/values-prometheus-stack.yaml
#
# Usage (from repo root):
#   ./testing/debug-prometheus-stack.sh
#
# Env: NAMESPACE_MONITORING (default: monitoring), RELEASE_NAME (default: prometheus-stack)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIKI_MANIFEST="$SCRIPT_DIR/test-wiki-stack.yaml"
STACK_VALUES="$SCRIPT_DIR/values-prometheus-stack.yaml"
RELEASE_NAME="${RELEASE_NAME:-prometheus-stack}"
NAMESPACE="${NAMESPACE_MONITORING:-monitoring}"
ERR=0

echo "=== Debug: existing deployment (test-wiki-stack + values-prometheus-stack) ==="
echo "  Wiki stack:   $WIKI_MANIFEST"
echo "  Stack values: $STACK_VALUES"
echo "  Helm release: $RELEASE_NAME (namespace: $NAMESPACE)"
echo ""

# --- 1. Wiki stack (test-wiki-stack.yaml) in cluster ---
echo "=== 1. Wiki stack (test-wiki-stack.yaml) in cluster ==="
if ! kubectl get namespace default &>/dev/null; then
  echo "  SKIP: cannot access cluster (kubectl / default namespace)"
  ((ERR++)) || true
else
  if kubectl get deployment wiki-api -n default &>/dev/null; then
    echo "  OK   Deployment wiki-api exists (default)"
  else
    echo "  FAIL Deployment wiki-api not found. Apply: kubectl apply -f $WIKI_MANIFEST"
    ((ERR++)) || true
  fi

  if kubectl get service wiki-api-service -n default &>/dev/null; then
    echo "  OK   Service wiki-api-service exists (default)"
    LABEL=$(kubectl get service wiki-api-service -n default -o jsonpath='{.metadata.labels.app}' 2>/dev/null || true)
    if [[ "$LABEL" == "wiki-api" ]]; then
      echo "  OK   Service has label app=wiki-api (required for ServiceMonitor selector)"
    else
      echo "  FAIL Service missing label app=wiki-api (got: '$LABEL'). ServiceMonitor selects matchLabels.app=wiki-api."
      echo "  Live Service metadata.labels (what the cluster has):"
      kubectl get service wiki-api-service -n default -o jsonpath='{.metadata.labels}' 2>/dev/null && echo "" || echo "       (none or error)"
      echo ""
      echo "  Manifest has metadata.labels.app=wiki-api. If the Service was created before that was added, or by another tool (e.g. Helm), the label is missing. Fix:"
      echo "       kubectl label svc wiki-api-service -n default app=wiki-api --overwrite"
      echo "       or re-apply: kubectl apply -f $WIKI_MANIFEST"
      ((ERR++)) || true
    fi
    PORT_NAME=$(kubectl get service wiki-api-service -n default -o jsonpath='{.spec.ports[0].name}' 2>/dev/null || true)
    if [[ "$PORT_NAME" == "http" ]]; then
      echo "  OK   Service port name is 'http' (matches values-prometheus-stack endpoints.port)"
    else
      echo "  FAIL Service port name should be 'http' (got: $PORT_NAME). values-prometheus-stack.yaml expects port: http"
      ((ERR++)) || true
    fi
  else
    echo "  FAIL Service wiki-api-service not found. Apply: kubectl apply -f $WIKI_MANIFEST"
    ((ERR++)) || true
  fi
fi
echo ""

# --- 2. Helm release and ServiceMonitor (values-prometheus-stack.yaml) ---
echo "=== 2. Helm release and ServiceMonitor (values-prometheus-stack) ==="
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "  FAIL Namespace $NAMESPACE missing. Install stack: ./testing/install-helm-dep.sh (uses $STACK_VALUES)"
  ((ERR++)) || true
else
  if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$RELEASE_NAME"; then
    echo "  OK   Helm release $RELEASE_NAME is installed in $NAMESPACE"
    INSTALLED_VALUES=$(helm get values "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 2 "additionalServiceMonitors" || true)
    if [[ -n "$INSTALLED_VALUES" ]]; then
      echo "  OK   Release has additionalServiceMonitors in values"
    else
      echo "  WARN Release may not have been installed with values-prometheus-stack.yaml (no additionalServiceMonitors in helm get values)"
    fi
  else
    echo "  FAIL Helm release $RELEASE_NAME not found in $NAMESPACE. Install: STACK_VALUES=$STACK_VALUES ./testing/install-helm-dep.sh"
    ((ERR++)) || true
  fi

  echo "  ServiceMonitors in $NAMESPACE:"
  if kubectl get servicemonitor -n "$NAMESPACE" 2>/dev/null; then
    if kubectl get servicemonitor -n "$NAMESPACE" -o name 2>/dev/null | grep -qE "wiki-api|prometheus-stack-wiki-api"; then
      echo "  OK   wiki-api ServiceMonitor exists (chart or testing/servicemonitor-wiki-api.yaml)"
    else
      echo "  FAIL No wiki-api ServiceMonitor in $NAMESPACE. Run: kubectl apply -f $SCRIPT_DIR/servicemonitor-wiki-api.yaml -n $NAMESPACE"
      echo "       Then: kubectl label servicemonitor prometheus-stack-wiki-api -n $NAMESPACE release=$RELEASE_NAME --overwrite"
      echo "       Or re-run full install: ./testing/install-helm-dep.sh"
      ((ERR++)) || true
    fi
  else
    echo "  FAIL Could not list ServiceMonitors (CRD or RBAC?)"
    ((ERR++)) || true
  fi
fi
echo ""

# --- 3. Grafana dashboard (creation) ---
echo "=== 3. Grafana dashboard (creation) ==="
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  DASH=$(kubectl get configmap -n "$NAMESPACE" -l grafana_dashboard=1 -o name 2>/dev/null | head -5)
  if [[ -n "$DASH" ]]; then
    echo "  OK   ConfigMap(s) with label grafana_dashboard=1: $DASH"
  else
    echo "  WARN No ConfigMaps with grafana_dashboard=1. install-helm-dep.sh creates creation-dashboard from wiki-chart/dashboards/creation-dashboard.json"
  fi
else
  echo "  SKIP namespace $NAMESPACE not found"
fi
echo ""

# --- 4. Helm template (optional; ServiceMonitor is applied by install-helm-dep.sh) ---
echo "=== 4. Helm template (wiki-api ServiceMonitor) ==="
RENDERED="$SCRIPT_DIR/.debug-prometheus-stack-rendered.yaml"
if helm template "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  -f "$STACK_VALUES" \
  > "$RENDERED" 2>&1; then
  if grep -q "wiki-api" "$RENDERED" && grep -q "kind: ServiceMonitor" "$RENDERED"; then
    echo "  OK   Chart renders wiki-api ServiceMonitor from values."
  else
    echo "  INFO Chart does not render wiki-api ServiceMonitor from values. install-helm-dep.sh applies testing/servicemonitor-wiki-api.yaml instead."
  fi
  echo "  Rendered: $RENDERED"
else
  echo "  WARN helm template failed (repo/network?). ServiceMonitor is still applied by install-helm-dep.sh (step 4)."
fi
echo ""

# --- 5. Prometheus scraping wiki-api? (target up + wiki metrics present) ---
echo "=== 5. Prometheus scraping wiki-api /metrics? ==="
PROM_SVC="${RELEASE_NAME}-kube-prom-prometheus"
# Some chart versions use a different service name
if ! kubectl get svc "$PROM_SVC" -n "$NAMESPACE" &>/dev/null; then
  PROM_SVC=$(kubectl get svc -n "$NAMESPACE" -o name 2>/dev/null | grep -i prometheus | head -1 | sed 's|.*/||') || true
fi
PF_PID=""
if [[ -n "$PROM_SVC" ]] && kubectl get svc "$PROM_SVC" -n "$NAMESPACE" &>/dev/null; then
  kubectl port-forward -n "$NAMESPACE" "svc/$PROM_SVC" 9090:9090 &>/dev/null &
  PF_PID=$!
  sleep 2
  CURL_OPTS="-s --max-time 5"
  # Query: is the wiki-api target up? (job label may be "wiki-api" or from ServiceMonitor name)
  UP_JSON=$(curl $CURL_OPTS "http://127.0.0.1:9090/api/v1/query?query=up%7Bjob%3D~%22.*wiki.*%22%7D" 2>/dev/null || true)
  # Query: do we have wiki app metrics? (creation dashboard uses users_created_total, posts_created_total)
  METRIC_JSON=$(curl $CURL_OPTS "http://127.0.0.1:9090/api/v1/query?query=users_created_total%20or%20posts_created_total" 2>/dev/null || true)
  kill $PF_PID 2>/dev/null || true
  wait $PF_PID 2>/dev/null || true
  if echo "$UP_JSON" | grep -q '"status":"success"' && echo "$UP_JSON" | grep -q '"result":\[{"metric"' && echo "$UP_JSON" | grep -qE '"value":\[[0-9.]+,"1"\]'; then
    echo "  OK   wiki-api target is up (Prometheus is scraping the job)."
  elif echo "$UP_JSON" | grep -q '"status":"success"' && echo "$UP_JSON" | grep -q '"result":\[\]'; then
    echo "  FAIL wiki-api target not in Prometheus. Check: ServiceMonitor present, Service has label app=wiki-api, Prometheus selector matches. UI: kubectl port-forward -n $NAMESPACE svc/$PROM_SVC 9090:9090 -> http://localhost:9090/targets"
    ((ERR++)) || true
  else
    echo "  FAIL Could not query Prometheus or target not up. If port 9090 is in use, run: lsof -i :9090. Then: kubectl port-forward -n $NAMESPACE svc/$PROM_SVC 9090:9090 and open http://localhost:9090/targets"
    ((ERR++)) || true
  fi
  if [[ -n "$METRIC_JSON" ]] && echo "$METRIC_JSON" | grep -q '"status":"success"' && echo "$METRIC_JSON" | grep -qE 'users_created_total|posts_created_total'; then
    echo "  OK   Wiki metrics in Prometheus (users_created_total / posts_created_total). Dashboard will have data."
  else
    echo "  WARN Wiki metrics not in Prometheus yet. Ensure app exposes /metrics (and has had some API traffic so counters exist)."
  fi
else
  echo "  SKIP Prometheus service $PROM_SVC not found in $NAMESPACE (cannot check scrape)."
fi
echo ""

# --- Summary ---
echo "=== Summary ==="
if [[ $ERR -eq 0 ]]; then
  echo "  All checks passed. Wiki stack and Prometheus stack are aligned."
else
  echo "  $ERR check(s) failed. Fix items above then re-run."
  echo "  Quick fixes:"
  echo "    - Wiki / Service label: kubectl apply -f $WIKI_MANIFEST   or   kubectl label svc wiki-api-service -n default app=wiki-api --overwrite"
  echo "    - Stack + ServiceMonitor: ./testing/install-helm-dep.sh (applies servicemonitor-wiki-api.yaml)"
fi
exit $ERR
