{{/*
Override Garage 0.8.0's Secret-content helper, which otherwise generates random
values independently for its Secret and pod checksum. Parent-chart helpers take
precedence over dependency helpers. Revisit this override when changing Garage's
chart version.
*/}}
{{- define "garage.secret.content" -}}
{{- $cacheKey := "_bookwyrmGarageSecretContent" -}}
{{- if hasKey .Values $cacheKey -}}
{{- index .Values $cacheKey -}}
{{- else -}}
{{- $config := .Values.garage.secret -}}
{{- $name := include "garage.secretName" . -}}
{{- if not $config.create -}}
{{/* External credential changes are managed by the Secret owner. */}}
{{- $content := printf "existingSecret: %s" $name -}}
{{- $_ := set .Values $cacheKey $content -}}
{{- $content -}}
{{- else -}}
{{- $previous := lookup "v1" "Secret" .Release.Namespace $name -}}
{{- $data := include "bookwyrm.garageSecretData" (dict "config" $config "previous" (dig "data" (dict) ($previous | default dict)) "webui" .Values.webui) -}}
{{- $_ := set .Values $cacheKey $data -}}
{{- $data -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Explicit values override retained data; generate only missing credentials. */}}
{{- define "bookwyrm.garageSecretData" -}}
{{- $data := dict -}}
{{- range $key := list "rpcSecret" "adminToken" -}}
{{- $value := index $.config $key -}}
{{- if $value -}}
{{- $_ := set $data $key ($value | b64enc) -}}
{{- else if index $.previous $key -}}
{{- $_ := set $data $key (index $.previous $key) -}}
{{- else -}}
{{- $_ := set $data $key (randAlphaNum 64 | sha256sum | b64enc) -}}
{{- end -}}
{{- end -}}
{{- if and .webui.enabled .webui.auth.enabled (not .webui.auth.existingSecret) -}}
{{- $hash := .webui.auth.userPassHash -}}
{{- if $hash -}}
{{- $_ := set $data "webuiAuthUserPass" ($hash | b64enc) -}}
{{- else if index .previous "webuiAuthUserPass" -}}
{{- $_ := set $data "webuiAuthUserPass" (index .previous "webuiAuthUserPass") -}}
{{- else -}}
{{- fail "garage.webui.auth.userPassHash is required when WebUI auth is enabled without an existing Secret" -}}
{{- end -}}
{{- end -}}
{{- toYaml $data -}}
{{- end -}}
