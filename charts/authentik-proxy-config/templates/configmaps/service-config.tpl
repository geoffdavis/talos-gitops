apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "authentik-proxy-config.fullname" . }}-service-config
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "authentik-proxy-config.labels" . | nindent 4 }}
    app.kubernetes.io/component: configuration
data:
  services.json: |
    {
      {{- $services := dict }}
      {{- range $key, $service := .Values.services }}
      {{- if $service.enabled }}
      {{- $_ := set $services $key $service }}
      {{- end }}
      {{- end }}
      {{- $serviceList := list }}
      {{- range $key, $service := $services }}
      {{- $serviceConfig := dict "key" $key "name" $service.name "slug" $service.slug "externalHost" $service.externalHost "internalHost" $service.internalHost "description" $service.description "publisher" $service.publisher }}
      {{- $serviceList = append $serviceList $serviceConfig }}
      {{- end }}
      "services": {{ $serviceList | toJson }}
    }
  
  authentik-config.json: |
    {
      "host": {{ .Values.authentik.host | quote }},
      "authFlowUuid": {{ .Values.authentik.authFlowUuid | quote }},
      "proxyProvider": {
        "mode": {{ .Values.proxyProvider.mode | quote }},
        "cookieDomain": {{ .Values.proxyProvider.cookieDomain | quote }},
        "skipPathRegex": {{ .Values.proxyProvider.skipPathRegex | quote }},
        "basicAuthEnabled": {{ .Values.proxyProvider.basicAuthEnabled }},
        "internalHostSslValidation": {{ .Values.proxyProvider.internalHostSslValidation }}
      },
      "outpost": {
        "name": {{ .Values.outpost.name | quote }},
        "namespace": {{ .Values.outpost.namespace | quote }}
      },
      "hooks": {
        "timeout": {{ .Values.hooks.timeout }},
        "retries": {{ .Values.hooks.retries }},
        "backoff": {{ .Values.hooks.backoff }}
      }
    }