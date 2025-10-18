{{- define "cb.routeHost" -}}
{{- $host := .Values.route.host | default "" -}}
{{- if $host -}}{{ $host }}{{- else -}}
  {{- if .Values.baseDomain -}}
    {{- printf "cb.%s" .Values.baseDomain -}}
  {{- else -}}
    {{- "" -}}
  {{- end -}}
{{- end -}}
{{- end -}}
