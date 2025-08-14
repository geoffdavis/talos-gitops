apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "authentik-proxy-config.fullname" . }}-pre-install-readiness
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "authentik-proxy-config.labels" . | nindent 4 }}
    app.kubernetes.io/component: pre-install-hook
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "-5"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ .Values.hooks.retries }}
  activeDeadlineSeconds: {{ .Values.hooks.timeout }}
  template:
    metadata:
      labels:
        {{- include "authentik-proxy-config.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: pre-install-hook
    spec:
      restartPolicy: OnFailure
      serviceAccountName: {{ include "authentik-proxy-config.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.securityContext | nindent 8 }}
      containers:
        - name: readiness-check
          image: {{ .Values.hooks.image }}
          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}
          env:
            - name: AUTHENTIK_HOST
              value: {{ .Values.authentik.host | quote }}
            - name: AUTHENTIK_TOKEN
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.externalSecrets.tokenSecretName }}
                  key: {{ .Values.externalSecrets.tokenSecretKey }}
            - name: MAX_RETRIES
              value: {{ .Values.hooks.retries | quote }}
            - name: BACKOFF_SECONDS
              value: {{ .Values.hooks.backoff | quote }}
          command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "=== Authentik Proxy Configuration Pre-Install Readiness Check ==="
              
              # Install curl
              apk add --no-cache curl

              # Function to check Authentik server readiness
              check_authentik_server() {
                echo "Checking Authentik server readiness..."
                local attempt=0
                local max_attempts=${MAX_RETRIES}

                while [ $attempt -lt $max_attempts ]; do
                  if curl -f -s "${AUTHENTIK_HOST}/-/health/live/" > /dev/null 2>&1; then
                    echo "✓ Authentik server is ready!"
                    return 0
                  fi
                  attempt=$((attempt + 1))
                  echo "Authentik not ready yet, attempt $attempt/$max_attempts, waiting ${BACKOFF_SECONDS} seconds..."
                  sleep ${BACKOFF_SECONDS}
                done

                echo "✗ ERROR: Authentik server did not become ready within $((max_attempts * BACKOFF_SECONDS)) seconds"
                return 1
              }

              # Function to validate admin token
              validate_admin_token() {
                echo "Validating admin token..."
                local attempt=0
                local max_attempts=${MAX_RETRIES}

                while [ $attempt -lt $max_attempts ]; do
                  response=$(curl -s -w "%{http_code}" -o /dev/null \
                    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
                    "${AUTHENTIK_HOST}/api/v3/core/users/me/")

                  if [ "$response" = "200" ]; then
                    echo "✓ Admin token is valid!"
                    return 0
                  fi

                  attempt=$((attempt + 1))
                  echo "Admin token not valid yet, attempt $attempt/$max_attempts (HTTP $response), waiting ${BACKOFF_SECONDS} seconds..."
                  sleep ${BACKOFF_SECONDS}
                done

                echo "✗ ERROR: Admin token did not become valid within $((max_attempts * BACKOFF_SECONDS)) seconds"
                echo "Please check the token in secret '${AUTHENTIK_TOKEN_SECRET_NAME}'"
                return 1
              }

              # Function to verify required secrets exist
              verify_secrets() {
                echo "Verifying required secrets exist..."

                if [ -z "${AUTHENTIK_TOKEN}" ]; then
                  echo "✗ ERROR: AUTHENTIK_TOKEN environment variable is empty"
                  echo "This indicates the secret '{{ .Values.externalSecrets.tokenSecretName }}' is not properly mounted"
                  return 1
                fi
                echo "✓ Required secrets are present and mounted"
                return 0
              }

              # Function to test API connectivity
              test_api_connectivity() {
                echo "Testing API connectivity..."

                if curl -s -f "${AUTHENTIK_HOST}/api/v3/root/config/" > /dev/null 2>&1; then
                  echo "✓ API connectivity test successful"
                  return 0
                else
                  echo "✗ ERROR: Cannot connect to Authentik API"
                  return 1
                fi
              }

              # Run all checks
              echo "Starting readiness checks..."

              verify_secrets
              check_authentik_server
              validate_admin_token
              test_api_connectivity

              echo "=== All readiness checks passed! ==="
