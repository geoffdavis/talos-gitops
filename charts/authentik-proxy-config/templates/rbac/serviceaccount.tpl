{{- if .Values.rbac.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "authentik-proxy-config.serviceAccountName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "authentik-proxy-config.labels" . | nindent 4 }}
    app.kubernetes.io/component: rbac
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "-10"
    helm.sh/resource-policy: keep
automountServiceAccountToken: true
{{- end }}
