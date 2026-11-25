{{/* Common labels. Call with (dict "root" $ "name" <service>) */}}
{{- define "opspilot.labels" -}}
{{ include "opspilot.selectorLabels" . }}
app.kubernetes.io/part-of: opspilot
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end }}

{{/* Labels used in selectors. Must never change after first install. */}}
{{- define "opspilot.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{/* Full image reference: <prefix><name>:<tag> */}}
{{- define "opspilot.image" -}}
{{- $tag := .svc.tag | default .root.Values.image.tag -}}
{{ .root.Values.image.prefix }}{{ .name }}:{{ $tag }}
{{- end }}
