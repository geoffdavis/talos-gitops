{{/*
Expand the name of the chart.
*/}}
{{- define "gitops-lifecycle-management.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "gitops-lifecycle-management.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gitops-lifecycle-management.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "gitops-lifecycle-management.labels" -}}
helm.sh/chart: {{ include "gitops-lifecycle-management.chart" . }}
{{ include "gitops-lifecycle-management.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "gitops-lifecycle-management.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gitops-lifecycle-management.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "gitops-lifecycle-management.serviceAccountName" -}}
{{- if .Values.rbac.serviceAccount.create }}
{{- default (include "gitops-lifecycle-management.fullname" .) .Values.rbac.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.rbac.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "gitops-lifecycle-management.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Authentication hook labels
*/}}
{{- define "gitops-lifecycle-management.authHookLabels" -}}
{{ include "gitops-lifecycle-management.labels" . }}
app.kubernetes.io/component: authentication-hook
{{- end }}

{{/*
Service discovery controller labels
*/}}
{{- define "gitops-lifecycle-management.serviceDiscoveryLabels" -}}
{{ include "gitops-lifecycle-management.labels" . }}
app.kubernetes.io/component: service-discovery-controller
{{- end }}

{{/*
Database hook labels
*/}}
{{- define "gitops-lifecycle-management.databaseHookLabels" -}}
{{ include "gitops-lifecycle-management.labels" . }}
app.kubernetes.io/component: database-hook
{{- end }}

{{/*
Validation hook labels
*/}}
{{- define "gitops-lifecycle-management.validationHookLabels" -}}
{{ include "gitops-lifecycle-management.labels" . }}
app.kubernetes.io/component: validation-hook
{{- end }}

{{/*
Cleanup controller labels
*/}}
{{- define "gitops-lifecycle-management.cleanupLabels" -}}
{{ include "gitops-lifecycle-management.labels" . }}
app.kubernetes.io/component: cleanup-controller
{{- end }}

{{/*
Security context for hooks
*/}}
{{- define "gitops-lifecycle-management.hookSecurityContext" -}}
securityContext:
  runAsNonRoot: {{ .Values.authentication.hooks.securityContext.runAsNonRoot }}
  runAsUser: {{ .Values.authentication.hooks.securityContext.runAsUser }}
  runAsGroup: {{ .Values.authentication.hooks.securityContext.runAsGroup }}
  allowPrivilegeEscalation: {{ .Values.authentication.hooks.securityContext.allowPrivilegeEscalation }}
  readOnlyRootFilesystem: {{ .Values.authentication.hooks.securityContext.readOnlyRootFilesystem }}
  capabilities:
    drop: {{ .Values.authentication.hooks.securityContext.capabilities.drop | toYaml | nindent 6 }}
  seccompProfile:
    type: {{ .Values.authentication.hooks.securityContext.seccompProfile.type }}
{{- end }}

{{/*
Pod security context for hooks
*/}}
{{- define "gitops-lifecycle-management.hookPodSecurityContext" -}}
securityContext:
  runAsNonRoot: {{ .Values.authentication.hooks.securityContext.runAsNonRoot }}
  runAsUser: {{ .Values.authentication.hooks.securityContext.runAsUser }}
  runAsGroup: {{ .Values.authentication.hooks.securityContext.runAsGroup }}
  seccompProfile:
    type: {{ .Values.authentication.hooks.securityContext.seccompProfile.type }}
{{- end }}

{{/*
Security context for controllers
*/}}
{{- define "gitops-lifecycle-management.controllerSecurityContext" -}}
securityContext:
  runAsNonRoot: {{ .Values.serviceDiscovery.controller.securityContext.runAsNonRoot }}
  runAsUser: {{ .Values.serviceDiscovery.controller.securityContext.runAsUser }}
  runAsGroup: {{ .Values.serviceDiscovery.controller.securityContext.runAsGroup }}
  allowPrivilegeEscalation: {{ .Values.serviceDiscovery.controller.securityContext.allowPrivilegeEscalation }}
  readOnlyRootFilesystem: {{ .Values.serviceDiscovery.controller.securityContext.readOnlyRootFilesystem }}
  capabilities:
    drop: {{ .Values.serviceDiscovery.controller.securityContext.capabilities.drop | toYaml | nindent 6 }}
  seccompProfile:
    type: {{ .Values.serviceDiscovery.controller.securityContext.seccompProfile.type }}
{{- end }}

{{/*
Pod security context for controllers
*/}}
{{- define "gitops-lifecycle-management.controllerPodSecurityContext" -}}
securityContext:
  runAsNonRoot: {{ .Values.serviceDiscovery.controller.securityContext.runAsNonRoot }}
  runAsUser: {{ .Values.serviceDiscovery.controller.securityContext.runAsUser }}
  runAsGroup: {{ .Values.serviceDiscovery.controller.securityContext.runAsGroup }}
  seccompProfile:
    type: {{ .Values.serviceDiscovery.controller.securityContext.seccompProfile.type }}
{{- end }}

{{/*
Hook job template
*/}}
{{- define "gitops-lifecycle-management.hookJobTemplate" -}}
spec:
  backoffLimit: {{ .Values.authentication.hooks.backoffLimit }}
  activeDeadlineSeconds: {{ .Values.authentication.hooks.activeDeadlineSeconds }}
  ttlSecondsAfterFinished: {{ .Values.authentication.hooks.ttlSecondsAfterFinished }}
  template:
    metadata:
      labels:
        {{- include "gitops-lifecycle-management.authHookLabels" . | nindent 8 }}
      annotations:
        {{- include "gitops-lifecycle-management.annotations" . | nindent 8 }}
    spec:
      restartPolicy: OnFailure
      serviceAccountName: {{ include "gitops-lifecycle-management.serviceAccountName" . }}
      {{- include "gitops-lifecycle-management.hookPodSecurityContext" . | nindent 6 }}
{{- end }}

{{/*
Hook container template
*/}}
{{- define "gitops-lifecycle-management.hookContainerTemplate" -}}
image: "{{ .Values.authentication.hooks.image.repository }}:{{ .Values.authentication.hooks.image.tag }}"
imagePullPolicy: {{ .Values.authentication.hooks.image.pullPolicy }}
{{- include "gitops-lifecycle-management.hookSecurityContext" . | nindent 0 }}
volumeMounts:
  - name: tmp-volume
    mountPath: /tmp
env:
  - name: AUTHENTIK_HOST
    value: {{ .Values.global.authentikHost | quote }}
  - name: AUTHENTIK_TOKEN
    valueFrom:
      secretKeyRef:
        name: {{ .Values.authentication.authentik.token.secretName }}
        key: {{ .Values.authentication.authentik.token.secretKey }}
  - name: EXTERNAL_OUTPOST_ID
    valueFrom:
      secretKeyRef:
        name: {{ .Values.authentication.authentik.externalOutpost.secretName }}
        key: "outpost_id"
  - name: AUTHORIZATION_FLOW
    valueFrom:
      secretKeyRef:
        name: {{ .Values.authentication.authentik.flows.secretName }}
        key: "authorization_flow"
  - name: INVALIDATION_FLOW
    valueFrom:
      secretKeyRef:
        name: {{ .Values.authentication.authentik.flows.secretName }}
        key: "invalidation_flow"
  - name: COOKIE_DOMAIN
    value: {{ .Values.authentication.authentik.cookieDomain | quote }}
{{- end }}

{{/*
Common volumes for hooks
*/}}
{{- define "gitops-lifecycle-management.hookVolumes" -}}
volumes:
  - name: tmp-volume
    emptyDir: {}
{{- end }}

{{/*
Authentik API connectivity test script
*/}}
{{- define "gitops-lifecycle-management.authentikConnectivityTest" -}}
set -e
echo "=== Testing Authentik API Connectivity ==="

# Validate required environment variables
if [ -z "${AUTHENTIK_HOST}" ] || [ -z "${AUTHENTIK_TOKEN}" ]; then
  echo "ERROR: Missing required environment variables"
  echo "AUTHENTIK_HOST: ${AUTHENTIK_HOST:-MISSING}"
  echo "AUTHENTIK_TOKEN: $([ -n "${AUTHENTIK_TOKEN}" ] && echo "SET" || echo "MISSING")"
  exit 1
fi

# Test Authentik API connectivity
echo "Testing Authentik API connectivity..."
if ! curl -s -f "${AUTHENTIK_HOST}/api/v3/core/users/me/" \
  -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" > /tmp/api_test.json; then
  echo "ERROR: Failed to connect to Authentik API"
  echo "Response:"
  cat /tmp/api_test.json 2>/dev/null || echo "No response received"
  exit 1
fi

echo "API connectivity test successful"
cat /tmp/api_test.json
{{- end }}

{{/*
Proxy provider creation function
*/}}
{{- define "gitops-lifecycle-management.proxyProviderFunction" -}}
# Function to create or update proxy provider
create_proxy_provider() {
  local name="$1"
  local external_host="$2"
  local internal_host="$3"
  local slug="$4"

  echo "Creating proxy provider: $name"

  # Check if provider already exists
  curl -s "${AUTHENTIK_HOST}/api/v3/providers/proxy/?name=${name}" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" > /tmp/existing_${slug}.json

  EXISTING_COUNT=$(cat /tmp/existing_${slug}.json | grep -o '"count":[0-9]*' | cut -d':' -f2)
  
  if [ "$EXISTING_COUNT" != "0" ]; then
    echo "Provider '$name' already exists, updating if needed"
    PROVIDER_ID=$(cat /tmp/existing_${slug}.json | grep -o '"pk":[0-9]*' | head -1 | cut -d':' -f2)
  else
    # Create proxy provider
    if curl -s -X POST "${AUTHENTIK_HOST}/api/v3/providers/proxy/" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${name}\",
        \"external_host\": \"https://${external_host}\",
        \"internal_host\": \"${internal_host}\",
        \"authorization_flow\": \"${AUTHORIZATION_FLOW}\",
        \"invalidation_flow\": \"${INVALIDATION_FLOW}\",
        \"cookie_domain\": \"${COOKIE_DOMAIN}\",
        \"mode\": \"forward_single\",
        \"skip_path_regex\": \"^/api/.*$\",
        \"basic_auth_enabled\": false,
        \"internal_host_ssl_validation\": false
      }" > /tmp/provider_${slug}.json; then

      PROVIDER_ID=$(cat /tmp/provider_${slug}.json | grep -o '"pk":[0-9]*' | cut -d':' -f2)
      echo "Created provider ID: $PROVIDER_ID"
    else
      echo "ERROR: Failed to create proxy provider for $name"
      cat /tmp/provider_${slug}.json
      return 1
    fi
  fi

  if [ -n "$PROVIDER_ID" ] && [ "$PROVIDER_ID" != "" ]; then
    # Assign to external outpost
    echo "Assigning provider $PROVIDER_ID to outpost $EXTERNAL_OUTPOST_ID"
    
    # Get current outpost providers
    curl -s "${AUTHENTIK_HOST}/api/v3/outposts/instances/${EXTERNAL_OUTPOST_ID}/" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" > /tmp/outpost_current.json

    # Extract current provider IDs and add new one
    CURRENT_PROVIDERS=$(cat /tmp/outpost_current.json | \
      grep -o '"providers":\[[^]]*\]' | grep -o '[0-9]\+' | \
      tr '\n' ',' | sed 's/,$//')
    
    if [ -n "$CURRENT_PROVIDERS" ]; then
      # Check if provider is already assigned
      if echo "$CURRENT_PROVIDERS" | grep -q "$PROVIDER_ID"; then
        echo "Provider $PROVIDER_ID already assigned to outpost"
        return 0
      fi
      NEW_PROVIDERS="${CURRENT_PROVIDERS},${PROVIDER_ID}"
    else
      NEW_PROVIDERS="${PROVIDER_ID}"
    fi

    if curl -s -X PATCH "${AUTHENTIK_HOST}/api/v3/outposts/instances/${EXTERNAL_OUTPOST_ID}/" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"providers\": [${NEW_PROVIDERS}]}" > /tmp/outpost_update.json; then
      echo "Provider assigned to outpost successfully"
    else
      echo "ERROR: Failed to assign provider to outpost"
      cat /tmp/outpost_update.json
      return 1
    fi
  else
    echo "ERROR: Failed to extract provider ID"
    return 1
  fi
  
  echo "---"
  return 0
}
{{- end }}