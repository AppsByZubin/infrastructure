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

{{- define "botsquadron.secretName" -}}
{{- if .Values.secret.name -}}
{{- .Values.secret.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "botsquadron.fullname" . }}-secrets
{{- end -}}
{{- end -}}

{{- define "botsquadron.natsName" -}}
{{- if .Values.nats.nameOverride -}}
{{- .Values.nats.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "botsquadron.fullname" . }}-nats
{{- end -}}
{{- end -}}

{{- define "botsquadron.ordersystemName" -}}
{{- include "botsquadron.fullname" . }}-ordersystem
{{- end -}}

{{- define "botsquadron.natsURL" -}}
{{- default (printf "nats://%s:%v" (include "botsquadron.natsName" .) .Values.nats.service.clientPort) .Values.env.NATS_URL -}}
{{- end -}}

{{- define "botsquadron.ordersystemURL" -}}
{{- printf "http://%s:%v" (include "botsquadron.ordersystemName" .) .Values.ordersystem.service.port -}}
{{- end -}}

{{- define "botsquadron.image" -}}
{{- $root := index . "root" -}}
{{- $service := index . "service" -}}
{{- $image := index . "image" | default dict -}}
{{- $repo := default $root.Values.image.repository $image.repository -}}
{{- $tag := default (printf "%s-%s" $service $root.Values.image.tagSuffix) $image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
