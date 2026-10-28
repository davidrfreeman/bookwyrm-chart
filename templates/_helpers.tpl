{{/*
Expand the name of the chart.
*/}}
{{- define "bookwyrm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Resource-name base. Preserve release-name defaults and support an override. */}}
{{- define "bookwyrm.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Reserve room for suffixes so generated names fit Kubernetes DNS labels. */}}
{{- define "bookwyrm.resourceName" -}}
{{- $suffix := .suffix | default "" -}}
{{- $base := include "bookwyrm.fullname" .context -}}
{{- if $suffix -}}
{{- printf "%s-%s" ($base | trunc (int (sub 62 (len $suffix))) | trimSuffix "-") $suffix -}}
{{- else -}}
{{- $base -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "bookwyrm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "bookwyrm.labels" -}}
helm.sh/chart: {{ include "bookwyrm.chart" . }}
{{ include "bookwyrm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "bookwyrm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bookwyrm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Application image; use the pinned appVersion when no tag override is set. */}}
{{- define "bookwyrm.image" -}}
{{- $repository := required "image.repository must be set" .Values.image.repository -}}
{{- $tag := .Values.image.tag | default (printf "v%s" (trimPrefix "v" .Chart.AppVersion)) -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}

{{/* Use a caller-managed Secret when supplied, otherwise create a release-scoped one. */}}
{{- define "bookwyrm.secretName" -}}
{{- default (include "bookwyrm.resourceName" (dict "context" . "suffix" "env")) .Values.existingSecret -}}
{{- end -}}

{{/* The admin password Secret is separate from application environment Secrets. */}}
{{- define "bookwyrm.adminSecretName" -}}
{{- .Values.admin.existingSecret | default (include "bookwyrm.resourceName" (dict "context" . "suffix" "admin")) -}}
{{- end -}}

{{/* Application identity; API-enabled Garage bootstrap has a separate account. */}}
{{- define "bookwyrm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "bookwyrm.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
