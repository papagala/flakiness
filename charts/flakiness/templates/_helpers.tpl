{{/*
Fully-qualified image reference.
*/}}
{{- define "flakiness.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "flakiness.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Resolve a component's failure percentage, falling back to the global default.
Call with a dict: {{ include "flakiness.percentage" (dict "component" .Values.flakyDeployment "root" .) }}
*/}}
{{- define "flakiness.percentage" -}}
{{- $c := .component -}}
{{- if hasKey $c "percentageOfFailures" -}}
{{- $c.percentageOfFailures -}}
{{- else -}}
{{- .root.Values.percentageOfFailures -}}
{{- end -}}
{{- end -}}
