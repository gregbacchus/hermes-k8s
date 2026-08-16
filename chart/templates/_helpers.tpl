{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "hermes.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "hermes.fullname" -}}
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
{{- define "hermes.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels for all resources.
*/}}
{{- define "hermes.labels" -}}
helm.sh/chart: {{ include "hermes.chart" . }}
{{ include "hermes.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels for the workloads.
*/}}
{{- define "hermes.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hermes.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Labels for a specific component (gateway or dashboard).
*/}}
{{- define "hermes.componentLabels" -}}
{{ include "hermes.labels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Selector labels for a specific component.
*/}}
{{- define "hermes.componentSelectorLabels" -}}
{{ include "hermes.selectorLabels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Create the name of the service account to use.
component-scoped: value takes precedence; falls back to global serviceAccount config.
*/}}
{{- define "hermes.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else if eq .component "gateway" }}
{{- if .Values.gateway.serviceAccount.name }}
{{- .Values.gateway.serviceAccount.name }}
{{- else }}
{{- include "hermes.fullname" . | printf "%s-gateway" }}
{{- end }}
{{- else }}
{{- if .Values.dashboard.serviceAccount.name }}
{{- .Values.dashboard.serviceAccount.name }}
{{- else }}
{{- include "hermes.fullname" . | printf "%s-dashboard" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Whether to create a component-scoped service account.
*/}}
{{- define "hermes.serviceAccountCreate" -}}
{{- if eq .component "gateway" }}
{{- if (kindIs "bool" .Values.gateway.serviceAccount.create) }}{{ .Values.gateway.serviceAccount.create }}{{ else }}{{ .Values.serviceAccount.create }}{{ end }}
{{- else }}
{{- if (kindIs "bool" .Values.dashboard.serviceAccount.create) }}{{ .Values.dashboard.serviceAccount.create }}{{ else }}{{ .Values.serviceAccount.create }}{{ end }}
{{- end }}
{{- end }}

{{/*
Service account annotations for a component.
*/}}
{{- define "hermes.serviceAccountAnnotations" -}}
{{- if eq .component "gateway" }}
{{- if .Values.gateway.serviceAccount.annotations }}{{ toYaml .Values.gateway.serviceAccount.annotations }}{{ else }}{{ toYaml .Values.serviceAccount.annotations }}{{ end }}
{{- else }}
{{- if .Values.dashboard.serviceAccount.annotations }}{{ toYaml .Values.dashboard.serviceAccount.annotations }}{{ else }}{{ toYaml .Values.serviceAccount.annotations }}{{ end }}
{{- end }}
{{- end }}

{{/*
Return the component-scoped pod annotations.
*/}}
{{- define "hermes.podAnnotations" -}}
{{- if eq .component "gateway" }}
{{- merge (deepCopy .Values.podAnnotations) (default (dict) .Values.gateway.podAnnotations) | toYaml }}
{{- else }}
{{- merge (deepCopy .Values.podAnnotations) (default (dict) .Values.dashboard.podAnnotations) | toYaml }}
{{- end }}
{{- end }}
