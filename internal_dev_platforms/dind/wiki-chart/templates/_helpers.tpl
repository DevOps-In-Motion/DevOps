{{/*
Expand the name of the chart.
*/}}
{{- define "wiki-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "wiki-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "wiki-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "wiki-chart.labels" -}}
helm.sh/chart: {{ include "wiki-chart.chart" . }}
{{ include "wiki-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "wiki-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wiki-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "wiki-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "wiki-chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway API routes fullname (used by HTTPRoute/TCPRoute templates).
*/}}
{{- define "gateway-api-routes.fullname" -}}
{{- include "wiki-chart.fullname" . }}
{{- end }}

{{/*
Gateway API routes labels (used by HTTPRoute/TCPRoute templates).
*/}}
{{- define "gateway-api-routes.labels" -}}
{{- include "wiki-chart.labels" . }}
{{- end }}

{{/*
Gateway API fullname (used by Gateway/GatewayClass templates).
*/}}
{{- define "gateway-api.fullname" -}}
{{- include "wiki-chart.fullname" . }}
{{- end }}

{{/*
Gateway API labels (used by Gateway/GatewayClass templates).
*/}}
{{- define "gateway-api.labels" -}}
{{- include "wiki-chart.labels" . }}
{{- end }}

{{/*
Creation dashboard JSON (uid: creation-dashboard-678). Inlined so it works when chart is used as a dependency ( .Files is parent scope).
*/}}
{{- define "wiki-chart.creationDashboardJson" -}}
{"annotations":{"list":[]},"editable":true,"fiscalYearStartMonth":0,"graphTooltip":0,"id":null,"links":[],"liveNow":false,"panels":[{"datasource":{"type":"prometheus","uid":"prometheus"},"fieldConfig":{"defaults":{"color":{"mode":"palette-classic"},"custom":{"axisCenteredZero":false,"axisLabel":"","axisPlacement":"auto","drawStyle":"line","fillOpacity":10,"gradientMode":"none","hideFrom":{"legend":false,"tooltip":false,"viz":false},"lineInterpolation":"linear","lineWidth":1,"pointSize":5,"scaleDistribution":{"type":"linear"},"showPoints":"auto","spanNulls":false,"stacking":{"group":"A","mode":"none"},"thresholdsStyle":{"mode":"off"}},"mappings":[],"thresholds":{"mode":"absolute","steps":[{"color":"green","value":null},{"color":"red","value":80}]},"unit":"short"},"overrides":[]},"gridPos":{"h":8,"w":24,"x":0,"y":0},"id":1,"options":{"legend":{"displayMode":"list","placement":"bottom","showLegend":true}},"targets":[{"datasource":{"type":"prometheus","uid":"prometheus"},"editorMode":"code","expr":"rate(users_created_total[5m])","legendFormat":"Users created (rate)","range":true,"refId":"A"},{"datasource":{"type":"prometheus","uid":"prometheus"},"editorMode":"code","expr":"rate(posts_created_total[5m])","legendFormat":"Posts created (rate)","hide":false,"range":true,"refId":"B"}],"title":"Users and posts creation rate","type":"timeseries"}],"refresh":"10s","schemaVersion":38,"style":"dark","tags":["wiki","creation"],"templating":{"list":[]},"time":{"from":"now-1h","to":"now"},"timepicker":{},"timezone":"","title":"creation","uid":"creation-dashboard-678","version":1,"weekStart":""}
{{- end }}
