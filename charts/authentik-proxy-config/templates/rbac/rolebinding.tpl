{{- if .Values.rbac.create }}
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "authentik-proxy-config.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "authentik-proxy-config.labels" . | nindent 4 }}
    app.kubernetes.io/component: rbac
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "-8"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "authentik-proxy-config.fullname" . }}
subjects:
- kind: ServiceAccount
  name: {{ include "authentik-proxy-config.serviceAccountName" . }}
  namespace: {{ .Release.Namespace }}
{{- end }}
