{{- define "statuspage.labels" -}}
app.kubernetes.io/name: statuspage
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
