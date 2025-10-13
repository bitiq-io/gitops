{{- define "eso-vault-examples.externalsecret" -}}
{{- $root := index . 0 -}}
{{- $cfg := index . 1 -}}
{{- $name := index . 2 -}}
{{- if and $root.Values.enabled $cfg.enabled }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ $cfg.nameOverride | default $cfg.targetSecretName | quote }}
  namespace: {{ $cfg.targetNamespace | quote }}
spec:
  refreshInterval: {{ $cfg.refreshInterval | default "1m" | quote }}
  {{- $cfgSecretStoreRef := default (dict) $cfg.secretStoreRef }}
  {{- $defaultSecretStoreRef := default (dict "kind" "ClusterSecretStore") $root.Values.externalSecretDefaults.secretStoreRef }}
  {{- $resolvedKind := coalesce $cfgSecretStoreRef.kind $defaultSecretStoreRef.kind "ClusterSecretStore" }}
  {{- $resolvedName := coalesce $cfgSecretStoreRef.name $defaultSecretStoreRef.name }}
  secretStoreRef:
    kind: {{ $resolvedKind | quote }}
    {{- if not $resolvedName }}
    {{- fail "secretStoreRef.name must be provided via values or defaults" }}
    {{- end }}
    name: {{ $resolvedName | quote }}
  target:
    name: {{ $cfg.targetSecretName | quote }}
    creationPolicy: {{ $cfg.creationPolicy | default $root.Values.externalSecretDefaults.creationPolicy | default "Owner" | quote }}
    {{- if or $cfg.secretType $cfg.annotations }}
    template:
      {{- if $cfg.secretType }}
      type: {{ $cfg.secretType | quote }}
      {{- end }}
      {{- with $cfg.annotations }}
      metadata:
        annotations:
{{ toYaml . | indent 10 }}
      {{- end }}
    {{- end }}
  data:
  {{- range $item := $cfg.data }}
    - secretKey: {{ $item.secretKey | quote }}
      remoteRef:
        key: {{ $item.remoteRef.key | quote }}
        {{- with $item.remoteRef.property }}
        property: {{ . | quote }}
        {{- end }}
        {{- with $item.remoteRef.version }}
        version: {{ . | quote }}
        {{- end }}
  {{- end }}
{{- end -}}
{{- end -}}
