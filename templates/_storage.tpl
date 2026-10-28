{{/* S3 connection and credential names. */}}
{{- define "bookwyrm.s3Endpoint" -}}
{{- if .Values.garage.enabled -}}
http://{{ include "garage.fullname" .Subcharts.garage }}:{{ .Values.garage.service.ports.s3Api }}
{{- else -}}
{{- required "s3.endpointUrl is required" .Values.s3.endpointUrl -}}
{{- end -}}
{{- end -}}
{{- define "bookwyrm.s3SecretName" -}}
{{- if .Values.garage.enabled -}}
{{ include "bookwyrm.resourceName" (dict "context" . "suffix" "garage-s3") }}
{{- else -}}
{{ .Values.s3.existingSecret | default (include "bookwyrm.secretName" .) }}
{{- end -}}
{{- end -}}

{{- define "bookwyrm.s3UrlProtocol" -}}
{{- .Values.s3.urlProtocol | default (printf "%s:" (urlParse .Values.s3.endpointUrl).scheme) -}}
{{- end -}}
