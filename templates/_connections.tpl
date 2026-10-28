{{/* Use the same dependency helpers that name their Services and database user. */}}
{{- define "bookwyrm.postgresHost" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "postgresql.v1.primary.fullname" .Subcharts.postgresql -}}
{{- else -}}
{{- .Values.postgres.host -}}
{{- end -}}
{{- end -}}

{{- define "bookwyrm.postgresPort" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "postgresql.v1.service.port" .Subcharts.postgresql -}}
{{- else -}}
{{- .Values.postgres.port -}}
{{- end -}}
{{- end -}}

{{- define "bookwyrm.postgresDatabase" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "postgresql.v1.database" .Subcharts.postgresql -}}
{{- else -}}
{{- .Values.postgres.database -}}
{{- end -}}
{{- end -}}

{{- define "bookwyrm.postgresUser" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "postgresql.v1.username" .Subcharts.postgresql -}}
{{- else -}}
{{- .Values.postgres.user -}}
{{- end -}}
{{- end -}}

{{- define "bookwyrm.redisHost" -}}
{{- $dependency := index .context.Values .alias -}}
{{- if $dependency.enabled -}}
{{- printf "%s-master" (include "common.names.fullname" (index .context.Subcharts .alias)) -}}
{{- else -}}
{{- .externalHost -}}
{{- end -}}
{{- end -}}

{{- define "bookwyrm.redisPort" -}}
{{- $dependency := index .context.Values .alias -}}
{{- if $dependency.enabled -}}
{{- $dependency.master.service.ports.redis -}}
{{- else -}}
{{- .context.Values.redis.port -}}
{{- end -}}
{{- end -}}
