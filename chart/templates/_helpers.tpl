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
Create the name of the gateway service account to use.
*/}}
{{- define "hermes.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else if .Values.gateway.serviceAccount.name }}
{{- .Values.gateway.serviceAccount.name }}
{{- else }}
{{- include "hermes.fullname" . | printf "%s-gateway" }}
{{- end }}
{{- end }}

{{/*
Whether to create the gateway service account.
*/}}
{{- define "hermes.serviceAccountCreate" -}}
{{- if (kindIs "bool" .Values.gateway.serviceAccount.create) }}{{ .Values.gateway.serviceAccount.create }}{{ else }}{{ .Values.serviceAccount.create }}{{ end }}
{{- end }}

{{/*
Service account annotations for the gateway.
*/}}
{{- define "hermes.serviceAccountAnnotations" -}}
{{- if .Values.gateway.serviceAccount.annotations }}{{ toYaml .Values.gateway.serviceAccount.annotations }}{{ else }}{{ toYaml .Values.serviceAccount.annotations }}{{ end }}
{{- end }}

{{/*
Return the gateway pod annotations.
*/}}
{{- define "hermes.podAnnotations" -}}
{{- merge (deepCopy .Values.podAnnotations) (default (dict) .Values.gateway.podAnnotations) | toYaml }}
{{- end }}
