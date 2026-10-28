{{/* Shared application environment and container environment fields. */}}
{{- define "bookwyrm.env" -}}
- name: BOOKWYRM_ADMIN_USERNAME
  value: {{ .Values.admin.username | quote }}
- name: DOMAIN
  value: {{ .Values.domain | quote }}
- name: DEBUG
  value: "false"
- name: POSTGRES_HOST
  value: {{ include "bookwyrm.postgresHost" . | quote }}
- name: PGPORT
  value: {{ include "bookwyrm.postgresPort" . | quote }}
- name: POSTGRES_DB
  value: {{ include "bookwyrm.postgresDatabase" . | quote }}
- name: POSTGRES_USER
  value: {{ include "bookwyrm.postgresUser" . | quote }}
- name: REDIS_BROKER_HOST
  value: {{ include "bookwyrm.redisHost" (dict "context" . "alias" "redisBroker" "externalHost" .Values.redis.brokerHost) | quote }}
- name: REDIS_ACTIVITY_HOST
  value: {{ include "bookwyrm.redisHost" (dict "context" . "alias" "redisActivity" "externalHost" .Values.redis.activityHost) | quote }}
- name: REDIS_BROKER_PORT
  value: {{ include "bookwyrm.redisPort" (dict "context" . "alias" "redisBroker") | quote }}
- name: REDIS_ACTIVITY_PORT
  value: {{ include "bookwyrm.redisPort" (dict "context" . "alias" "redisActivity") | quote }}
- name: EMAIL_HOST
  value: {{ .Values.email.host | quote }}
- name: EMAIL_PORT
  value: {{ .Values.email.port | quote }}
- name: EMAIL_HOST_USER
  value: {{ .Values.email.user | quote }}
- name: EMAIL_SENDER_DOMAIN
  value: {{ .Values.email.senderDomain | quote }}
- name: EMAIL_USE_TLS
  value: {{ .Values.email.useTLS | quote }}
- name: EMAIL_USE_SSL
  value: "false"
- name: USE_S3
  value: "true"
- name: AWS_STORAGE_BUCKET_NAME
  value: {{ required "s3.bucket is required" .Values.s3.bucket | quote }}
- name: AWS_S3_ENDPOINT_URL
  value: {{ include "bookwyrm.s3Endpoint" . | quote }}
- name: AWS_S3_REGION_NAME
  value: {{ ternary .Values.garage.garage.s3.api.region .Values.s3.region .Values.garage.enabled | quote }}
- name: AWS_S3_CUSTOM_DOMAIN
  value: {{ required "s3.customDomain must point to the publicly readable asset bucket" .Values.s3.customDomain | quote }}
- name: AWS_S3_URL_PROTOCOL
  value: {{ include "bookwyrm.s3UrlProtocol" . | quote }}
- name: AWS_DEFAULT_ACL
  value: {{ .Values.s3.defaultAcl | quote }}
- name: USE_S3_FOR_EXPORTS
  value: "true"
- name: EXPORTS_S3_ENDPOINT_URL
  value: {{ .Values.s3.endpointUrl | quote }}
- name: EXPORTS_STORAGE_BUCKET_NAME
  value: {{ required "s3.exportsBucket must name a private bucket" .Values.s3.exportsBucket | quote }}
{{- if or .Values.garage.enabled .Values.s3.existingSecret }}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "bookwyrm.s3SecretName" . | quote }}
      key: AWS_ACCESS_KEY_ID
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "bookwyrm.s3SecretName" . | quote }}
      key: AWS_SECRET_ACCESS_KEY
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}
{{- define "bookwyrm.appEnv" -}}
imagePullPolicy: {{ .Values.image.pullPolicy }}
envFrom:
  - secretRef:
      name: {{ include "bookwyrm.secretName" . | quote }}
env:
{{ include "bookwyrm.env" . | indent 2 }}
{{- end -}}
