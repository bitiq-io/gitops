{{- define "ollama.mode" -}}
{{- $raw := default "disabled" .Values.mode -}}
{{- lower (printf "%v" $raw) -}}
{{- end -}}

{{- define "ollama.labels" -}}
app.kubernetes.io/name: ollama
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/part-of: bitiq
{{- end -}}

{{- define "ollama.externalHost" -}}
{{- $explicit := default "" .Values.external.host -}}
{{- if $explicit }}
{{- $explicit -}}
{{- else -}}
  {{- $prefix := default "ollama" .Values.external.hostPrefix -}}
  {{- $base := default "" .Values.baseDomain -}}
  {{- if $base -}}{{ printf "%s.%s" $prefix $base }}{{- else -}}{{ $prefix }}{{- end -}}
{{- end -}}
{{- end -}}

{{- define "ollama.externalURL" -}}
{{- $scheme := default "https" .Values.external.scheme -}}
{{- $host := include "ollama.externalHost" . -}}
{{- $port := default 11434 .Values.external.port -}}
{{- if and $host $port }}
{{- printf "%s://%s:%v" $scheme $host $port -}}
{{- else if $host }}
{{- printf "%s://%s" $scheme $host -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}
