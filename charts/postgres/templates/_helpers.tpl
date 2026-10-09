{{- define "postgres.fullname" -}}
{{- .Values.fullnameOverride | default .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "postgres.labels" -}}
{{ include "postgres.selectorLabels" . }}
app.kubernetes.io/part-of: telecom-gis
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
