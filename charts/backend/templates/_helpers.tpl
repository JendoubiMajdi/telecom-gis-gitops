{{- define "backend.fullname" -}}
{{- .Values.fullnameOverride | default .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "backend.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "backend.labels" -}}
{{ include "backend.selectorLabels" . }}
app.kubernetes.io/part-of: telecom-gis
app.kubernetes.io/version: {{ .Values.image.tag | toString | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
