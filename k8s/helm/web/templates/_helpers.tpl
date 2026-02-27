{{/*
Naming helpers — follow project convention: node--<env>--<k8s-component>--web
*/}}

{{- define "web.env" -}}
{{- .Values.env | default "prod" -}}
{{- end -}}

{{- define "web.fullname" -}}
{{- printf "node--%s--deploy--web" (include "web.env" .) -}}
{{- end -}}

{{- define "web.svcname" -}}
{{- printf "node--%s--svc--web" (include "web.env" .) -}}
{{- end -}}

{{- define "web.cmname" -}}
{{- printf "node--%s--cm--web" (include "web.env" .) -}}
{{- end -}}

{{- define "web.secretname" -}}
{{- printf "node--%s--secret--web" (include "web.env" .) -}}
{{- end -}}

{{- define "web.hpaname" -}}
{{- printf "node--%s--hpa--web" (include "web.env" .) -}}
{{- end -}}

{{- define "web.pdbname" -}}
{{- printf "node--%s--pdb--web" (include "web.env" .) -}}
{{- end -}}

{{- define "web.ingressname" -}}
{{- printf "node--%s--ingress--web" (include "web.env" .) -}}
{{- end -}}

{{/* Common labels */}}
{{- define "web.labels" -}}
app.kubernetes.io/name: node-web
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app: node-web
env: {{ include "web.env" . }}
owner: Ram
purpose: Toptal
{{- end -}}

{{/* Selector labels */}}
{{- define "web.selectorLabels" -}}
app.kubernetes.io/name: node-web
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
