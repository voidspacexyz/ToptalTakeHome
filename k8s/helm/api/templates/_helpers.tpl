{{/*
Naming helpers — follow project convention: node--<env>--<k8s-component>--api
*/}}

{{- define "api.env" -}}
{{- .Values.env | default "prod" -}}
{{- end -}}

{{- define "api.fullname" -}}
{{- printf "node--%s--deploy--api" (include "api.env" .) -}}
{{- end -}}

{{- define "api.svcname" -}}
{{- printf "node--%s--svc--api" (include "api.env" .) -}}
{{- end -}}

{{- define "api.cmname" -}}
{{- printf "node--%s--cm--api" (include "api.env" .) -}}
{{- end -}}

{{- define "api.secretname" -}}
{{- printf "node--%s--secret--api" (include "api.env" .) -}}
{{- end -}}

{{- define "api.hpaname" -}}
{{- printf "node--%s--hpa--api" (include "api.env" .) -}}
{{- end -}}

{{- define "api.pdbname" -}}
{{- printf "node--%s--pdb--api" (include "api.env" .) -}}
{{- end -}}

{{/* Common labels */}}
{{- define "api.labels" -}}
app.kubernetes.io/name: node-api
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app: node-api
env: {{ include "api.env" . }}
owner: Ram
purpose: Toptal
{{- end -}}

{{/* Selector labels */}}
{{- define "api.selectorLabels" -}}
app.kubernetes.io/name: node-api
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
