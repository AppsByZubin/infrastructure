{{- define "botsquadron.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "botsquadron.configMapName" -}}
{{- if .Values.configMap.name -}}
{{- .Values.configMap.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "botsquadron.fullname" . }}-env
{{- end -}}
{{- end -}}

{{- define "botsquadron.image" -}}
{{- $root := index . "root" -}}
{{- $service := index . "service" -}}
{{- $image := index . "image" | default dict -}}
{{- $repo := default $root.Values.image.repository $image.repository -}}
{{- $tag := default (printf "%s-%s" $service $root.Values.image.tagSuffix) $image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
