{{/* Wait for database migrations and required admin initialization. */}}
{{- define "bookwyrm.waitForInitialization" -}}
{{- if .Values.migration.waitForMigrations }}
- name: wait-for-migrations
  image: {{ include "bookwyrm.image" . | quote }}
  command: ["/bin/sh", "-ec"]
  args:
    - |
        until python manage.py migrate --check; do
          echo "Waiting for database migrations to finish..."
          sleep 5
        done
        until python manage.py shell <<'BOOKWYRM_READINESS_PY'
{{ .Files.Get "files/check-initialization.py" | indent 8 }}
        BOOKWYRM_READINESS_PY
        do
          echo "Waiting for admin initialization..."
          sleep 5
        done
  {{- include "bookwyrm.appEnv" . | nindent 2 }}
{{- end }}
{{- end -}}
