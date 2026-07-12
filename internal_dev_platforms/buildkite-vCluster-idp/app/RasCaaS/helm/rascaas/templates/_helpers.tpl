{{/*
Expand the name of the chart.
*/}}
{{- define "rascaas.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "rascaas.fullname" -}}
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
Chart label — version string safe for labels.
*/}}
{{- define "rascaas.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels for chart-owned resources.
*/}}
{{- define "rascaas.labels" -}}
helm.sh/chart: {{ include "rascaas.chart" . }}
{{ include "rascaas.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if and .Values.global .Values.global.environment }}
app.kubernetes.io/environment: {{ .Values.global.environment | quote }}
{{- end }}
{{- end }}

{{/*
Selector labels for the release.
*/}}
{{- define "rascaas.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rascaas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
FastAPI workload selector labels.
*/}}
{{- define "rascaas.fastapi.selectorLabels" -}}
app: {{ .Values.fastapi.name }}
app.kubernetes.io/name: {{ .Values.fastapi.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: fastapi
{{- end }}

{{/*
FastAPI deployment/service labels.
*/}}
{{- define "rascaas.fastapi.labels" -}}
{{ include "rascaas.fastapi.selectorLabels" . }}
{{- range $k, $v := .Values.fastapi.labels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}

{{/*
oauth2-proxy workload selector labels.
*/}}
{{- define "rascaas.oauth2proxy.selectorLabels" -}}
app: {{ .Values.oauth2proxy.name }}
app.kubernetes.io/name: {{ .Values.oauth2proxy.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: oauth2-proxy
{{- end }}

{{/*
oauth2-proxy deployment/service labels.
*/}}
{{- define "rascaas.oauth2proxy.labels" -}}
{{ include "rascaas.oauth2proxy.selectorLabels" . }}
{{- range $k, $v := .Values.oauth2proxy.labels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}

{{/*
Service account for oauth2-proxy pods.
*/}}
{{- define "rascaas.oauth2proxy.serviceAccountName" -}}
{{- if .Values.oauth2proxy.serviceAccountName }}
{{- .Values.oauth2proxy.serviceAccountName }}
{{- else }}
{{- printf "%s-sa" .Values.oauth2proxy.name }}
{{- end }}
{{- end }}

{{/*
Helm release namespace.
*/}}
{{- define "rascaas.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Gateway API parent namespace (defaults to release namespace).
*/}}
{{- define "rascaas.gateway.namespace" -}}
{{- .Values.gateway.namespace | default .Release.Namespace }}
{{- end }}

{{/*
Gateway API parent name.
*/}}
{{- define "rascaas.gateway.name" -}}
{{- .Values.gateway.name }}
{{- end }}

{{/*
Service account for FastAPI pods.
*/}}
{{- define "rascaas.fastapi.serviceAccountName" -}}
{{- if .Values.fastapi.serviceAccountName }}
{{- .Values.fastapi.serviceAccountName }}
{{- else }}
{{- printf "%s-sa" .Values.fastapi.name }}
{{- end }}
{{- end }}

{{/*
Bundled Keycloak service name (Bitnami subchart).
*/}}
{{- define "rascaas.keycloak.serviceName" -}}
{{- if .Values.keycloak.fullnameOverride -}}
{{- .Values.keycloak.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-keycloak" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
ConfigMap for keycloak-config-cli realm import (release-scoped name).
*/}}
{{- define "rascaas.keycloak.realmConfigMapName" -}}
{{- printf "%s-keycloak-realm" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Public app base URL (no trailing slash).
*/}}
{{- define "rascaas.appBaseUrl" -}}
{{- trimSuffix "/" (.Values.fastapi.env.APP_BASE_URL | default "http://localhost:4180") -}}
{{- end -}}

{{/*
In-cluster Keycloak HTTP base (Bitnami service port 80).
*/}}
{{- define "rascaas.keycloak.internalHttpBase" -}}
{{- $path := trimSuffix "/" (.Values.keycloak.httpRelativePath | default "/") -}}
{{- if eq $path "/" -}}
{{- printf "http://%s" (include "rascaas.keycloak.serviceName" .) -}}
{{- else -}}
{{- printf "http://%s%s" (include "rascaas.keycloak.serviceName" .) $path -}}
{{- end -}}
{{- end -}}

{{/*
OIDC issuer URL for oauth2-proxy / FastAPI (browser-facing when publicBaseUrl is set).
*/}}
{{- define "rascaas.oidc.issuerUrl" -}}
{{- if .Values.keycloak.enabled -}}
{{- $base := .Values.keycloak.publicBaseUrl | default (include "rascaas.keycloak.internalHttpBase" .) -}}
{{- printf "%s/realms/%s" (trimSuffix "/" $base) .Values.keycloak.realm -}}
{{- else -}}
{{- .Values.oauth2proxy.oidcIssuerUrl -}}
{{- end -}}
{{- end -}}

{{/*
In-cluster Keycloak OIDC JWKS URL (token validation from pods).
*/}}
{{- define "rascaas.keycloak.internalOidcJwksUrl" -}}
{{- printf "%s/realms/%s/protocol/openid-connect/certs" (include "rascaas.keycloak.internalHttpBase" .) .Values.keycloak.realm -}}
{{- end -}}

{{/*
In-cluster Keycloak token endpoint for oauth2-proxy.
*/}}
{{- define "rascaas.keycloak.internalOidcTokenUrl" -}}
{{- printf "%s/realms/%s/protocol/openid-connect/token" (include "rascaas.keycloak.internalHttpBase" .) .Values.keycloak.realm -}}
{{- end -}}

{{/*
Upstream URL for oauth2-proxy (defaults to in-cluster FastAPI service).
*/}}
{{- define "rascaas.oauth2proxy.upstream" -}}
{{- if .Values.oauth2proxy.upstreamUrl }}
{{- .Values.oauth2proxy.upstreamUrl }}
{{- else }}
{{- printf "http://%s:%v" .Values.fastapi.name .Values.fastapi.port }}
{{- end }}
{{- end }}

{{/*
Validate secrets.mode and CSI prerequisites.
*/}}
{{- define "rascaas.secrets.validate" -}}
{{- $mode := .Values.secrets.mode | default "csi-driver" -}}
{{- if not (or (eq $mode "csi-driver") (eq $mode "plain")) -}}
{{- fail (printf "secrets.mode must be \"csi-driver\" or \"plain\", got %q" $mode) -}}
{{- end -}}
{{- if and (eq $mode "csi-driver") (not .Values.secrets.secretProviderClass) -}}
{{- fail "secrets.secretProviderClass is required when secrets.mode is csi-driver" -}}
{{- end -}}
{{- end -}}

{{/*
True when pods should mount the secrets-store CSI volume (AWS SM → SPC).
*/}}
{{- define "rascaas.secrets.csiEnabled" -}}
{{- if eq (.Values.secrets.mode | default "csi-driver") "csi-driver" -}}
true
{{- end -}}
{{- end -}}

{{/*
CSI volume on the pod spec (secrets.mode=csi-driver only).
*/}}
{{- define "rascaas.pod.csiVolumes" -}}
{{- if eq (include "rascaas.secrets.csiEnabled" .) "true" }}
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: {{ .Values.secrets.secretProviderClass }}
{{- end }}
{{- end -}}

{{/*
CSI volumeMount on a container (secrets.mode=csi-driver only).
*/}}
{{- define "rascaas.container.csiVolumeMounts" -}}
{{- if eq (include "rascaas.secrets.csiEnabled" .) "true" }}
          volumeMounts:
            - name: secrets-store
              mountPath: {{ .Values.secrets.mountPath | default "/mnt/secrets-store" }}
              readOnly: true
{{- end }}
{{- end -}}

{{/*
Image pull secrets (optional).
*/}}
{{- define "rascaas.imagePullSecrets" -}}
{{- if and .Values.global .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml .Values.global.imagePullSecrets | nindent 2 }}
{{- end }}
{{- end }}
