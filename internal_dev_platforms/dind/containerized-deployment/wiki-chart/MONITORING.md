#  Wiki-Chart Monitoring (Prometheus + Grafana)

## Namespace (Prometheus, Alertmanager, Grafana)

The chart sets `prometheus-stack.namespaceOverride: monitoring` and component-level `namespaceOverride: monitoring` for **alertmanager**, **prometheus**, and **grafana** so all stack components deploy into the `monitoring` namespace. The chart also creates the `monitoring` namespace when `prometheusStack.createMonitoringNamespace` is true.

If **Grafana** still appears in the release namespace (e.g. `wiki-api`) instead of `monitoring`, the Grafana subchart may not honor `namespaceOverride`. In that case either:

- Install the release into `monitoring` when using the full stack:  
  `helm upgrade --install wiki-api ./wiki-chart -n monitoring --create-namespace -f ./testing/helm-test-values-full.yaml`, or  
- Confirm with `helm get values wiki-api -n <your-namespace>` that `prometheus-stack.grafana.namespaceOverride` is `monitoring` and that your kube-prometheus-stack / Grafana subchart version supports it.

---

## 1. ServiceMonitor (created by kube-prometheus-stack)

- **How:** The chart adds the wiki app to the **prometheus-stack** subchart via `prometheus-stack.prometheus.prometheusSpec.additionalServiceMonitors`.
- **Where:** `values.yaml` → `prometheus-stack.prometheus.prometheusSpec.additionalServiceMonitors` (name: `wiki-api-servicemonitor`, selector: `app.kubernetes.io/name: backend`, namespaceSelector: `default`).
- **Match:** The wiki **Service** uses chart labels (selectorLabels), which include `app.kubernetes.io/name: backend`, so the ServiceMonitor selector matches. The ServiceMonitor scrapes the backend in the **default** namespace.
- **Port:** Service port name is `http`, endpoint path `/metrics`, interval 30s. App listens on `service.port` (default **8080**).

**If you install in a namespace other than `monitoring`:** Override the ServiceMonitor namespaceSelector, e.g.  
`prometheus-stack.prometheus.prometheusSpec.additionalServiceMonitors[0].namespaceSelector.matchNames: [default]`.

**If you set `nameOverride`:** Override the ServiceMonitor selector so it matches your Service, e.g.  
`prometheus-stack.prometheus.prometheusSpec.additionalServiceMonitors[0].selector.matchLabels.app.kubernetes.io/name: <your-name>`.

**Optional:** Set `prometheusStack.createServiceMonitor: true` to have the **chart** create a ServiceMonitor instead of the stack (template: `templates/servicemonitor-wiki.yaml`).

---

## 2. Dashboard (pre-loaded via stack)

- **How:** The chart creates a **ConfigMap** with the creation dashboard JSON and label `grafana_dashboard: "1"`.
- **Where:** `templates/grafana-dashboard-creation.yaml` (when `prometheusStack.enabled`).
- **Pick-up:** kube-prometheus-stack Grafana sidecar has `sidecar.dashboards.label: grafana_dashboard`, `labelValue: "1"`, `searchNamespace: ALL`, so it loads this ConfigMap in the same namespace.
- **Dashboard:** uid `creation-dashboard-678`, panels for `rate(users_created_total[5m])` and `rate(posts_created_total[5m])`.

---

## 3. Naming and labels

| Resource      | Convention |
|---------------|------------|
| Service name  | `service.name` or default `{{ fullname }}` (e.g. `release-backend`) |
| Service port  | **8080** (wiki API); port **name** `http` for ServiceMonitor |
| Service labels| Chart labels → `app.kubernetes.io/name: backend`, `app.kubernetes.io/instance: <release>` |
| ServiceMonitor| Created by stack with selector `app.kubernetes.io/name: backend` (must match Service) |

---

## 4. Double-check after install

```bash
# Service has correct port and labels (backend in default)
kubectl get svc -n default -l app.kubernetes.io/name=backend -o yaml | grep -A2 "port:\|labels:" 

# ServiceMonitor exists (from stack; stack may be in monitoring or same as release)
kubectl get servicemonitor -n <stack-namespace> | grep wiki

# Dashboard ConfigMap
kubectl get configmap -n <stack-namespace> -l grafana_dashboard=1 | grep creation

# Prometheus target up (after port-forward to Prometheus)
# curl -s 'http://localhost:9090/api/v1/query?query=up{job=~".*wiki.*"}' 
```

Then in Grafana open the dashboard: **Dashboards → creation** (uid `creation-dashboard-678`).

---

## 5. Alignment with working plain-manifest setup

The setup that works with **testing/values-prometheus-stack.yaml** and **testing/test-wiki-stack.yaml** (plain manifests) is mirrored in this chart where possible:

| Item | values-prometheus-stack.yaml + test-wiki-stack | Helm chart (wiki-chart) | Status |
|------|------------------------------------------------|-------------------------|--------|
| ServiceMonitor name | `wiki-api-servicemonitor` | `wiki-api-servicemonitor` | Aligned |
| ServiceMonitor selector | `app: wiki-api` (plain Service) | `app.kubernetes.io/name: backend` (chart Service) | Different by design: chart uses standard labels |
| namespaceSelector | `matchNames: [default]` | `matchNames: [default]` (scrapes backend in default) | Aligned |
| Endpoints | port `http`, path `/metrics` | port `http`, path `/metrics`, interval 30s | Aligned |
| Grafana sidecar | label `grafana_dashboard=1`, searchNamespace ALL | Same | Aligned |
| Grafana datasource | Prometheus, url `http://prometheus:9090`, uid in dashboard | Prometheus, url `http://prometheus-operator-prometheus:9090`, uid `prometheus` | Aligned (chart uses stack fullname for URL) |
| Dashboard | Inline in values or ConfigMap | ConfigMap with label `grafana_dashboard=1`, inlined JSON | Aligned |

**If you use plain manifests (test-wiki-stack.yaml)** and install the stack with **values-prometheus-stack.yaml**, the Service has label `app: wiki-api`. The Helm chart deploys a Service with `app.kubernetes.io/name: backend`; to scrape that, the chart’s additionalServiceMonitors selector is set to `backend`. To scrape a legacy `app: wiki-api` Service as well, add a second entry under `additionalServiceMonitors` with `selector.matchLabels.app: wiki-api` and the same `namespaceSelector` / endpoints.
