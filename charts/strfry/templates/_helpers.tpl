{{- define "strfry.fullname" -}}
{{- printf "strfry-%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "strfry.routeHost" -}}
{{- $explicit := .Values.route.host | default "" -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else -}}
  {{- $prefix := default "relay" .Values.hostPrefix -}}
  {{- $base := default "" .Values.baseDomain -}}
  {{- if $base -}}{{ printf "%s.%s" $prefix $base }}{{- else -}}{{ printf "%s" $prefix }}{{- end -}}
{{- end -}}
{{- end -}}
