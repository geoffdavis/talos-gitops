apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "authentik-proxy-config.fullname" . }}-post-upgrade-config
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "authentik-proxy-config.labels" . | nindent 4 }}
    app.kubernetes.io/component: post-upgrade-hook
  annotations:
    helm.sh/hook: post-upgrade
    helm.sh/hook-weight: "1"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ .Values.hooks.retries }}
  activeDeadlineSeconds: {{ .Values.hooks.timeout }}
  template:
    metadata:
      labels:
        {{- include "authentik-proxy-config.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: post-upgrade-hook
    spec:
      restartPolicy: OnFailure
      serviceAccountName: {{ include "authentik-proxy-config.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.securityContext | nindent 8 }}
      containers:
        - name: update-proxies
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
            - name: AUTH_FLOW_UUID
              value: {{ .Values.authentik.authFlowUuid | quote }}
            - name: PROXY_MODE
              value: {{ .Values.proxyProvider.mode | quote }}
            - name: COOKIE_DOMAIN
              value: {{ .Values.proxyProvider.cookieDomain | quote }}
            - name: SKIP_PATH_REGEX
              value: {{ .Values.proxyProvider.skipPathRegex | quote }}
            - name: OUTPOST_NAME
              value: {{ .Values.outpost.name | quote }}
            - name: MAX_RETRIES
              value: {{ .Values.hooks.retries | quote }}
            - name: BACKOFF_SECONDS
              value: {{ .Values.hooks.backoff | quote }}
          volumeMounts:
            - name: service-config
              mountPath: /config
              readOnly: true
          command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "=== Authentik Proxy Configuration Post-Upgrade Hook ==="
              
              # Load service configuration
              SERVICES_JSON=$(cat /config/services.json)
              echo "Loaded service configuration for $(echo "$SERVICES_JSON" | grep -o '"key"' | wc -l) services"
              
              # Retry function for API calls
              retry_api_call() {
                local url="$1"
                local method="${2:-GET}"
                local data="${3:-}"
                local max_retries=${MAX_RETRIES}
                local retry_count=0
                
                while [ $retry_count -lt $max_retries ]; do
                  if [ "$method" = "POST" ] && [ -n "$data" ]; then
                    response=$(curl -s -w "%{http_code}" -o /tmp/api_response \
                      -X POST \
                      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
                      -H "Content-Type: application/json" \
                      -d "$data" \
                      "$url")
                  elif [ "$method" = "PATCH" ] && [ -n "$data" ]; then
                    response=$(curl -s -w "%{http_code}" -o /tmp/api_response \
                      -X PATCH \
                      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
                      -H "Content-Type: application/json" \
                      -d "$data" \
                      "$url")
                  else
                    response=$(curl -s -w "%{http_code}" -o /tmp/api_response \
                      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
                      "$url")
                  fi
                  
                  if [ "$response" = "200" ] || [ "$response" = "201" ]; then
                    return 0
                  fi
                  
                  retry_count=$((retry_count + 1))
                  if [ $retry_count -lt $max_retries ]; then
                    echo "API call failed with status $response, retry $retry_count/$max_retries"
                    sleep ${BACKOFF_SECONDS}
                  fi
                done
                
                echo "API call failed after $max_retries retries"
                cat /tmp/api_response
                return 1
              }
              
              # Function to update existing provider configuration
              update_service_config() {
                local service_key="$1"
                local service_name="$2"
                local service_slug="$3"
                local external_host="$4"
                local internal_host="$5"
                local description="$6"
                local publisher="$7"
                
                echo "=== Updating $service_name configuration ==="
                
                # Get existing provider
                echo "Looking for existing $service_key proxy provider..."
                if ! retry_api_call "${AUTHENTIK_HOST}/api/v3/providers/proxy/"; then
                  echo "Failed to check existing proxy providers"
                  return 1
                fi
                
                PROVIDER_RESPONSE=$(cat /tmp/api_response)
                PROVIDER_PK=$(echo "$PROVIDER_RESPONSE" | grep -A10 "\"name\":\"${service_key}-proxy\"" | grep -o '"pk":[0-9]*' | cut -d':' -f2)
                
                if [ -n "$PROVIDER_PK" ]; then
                  echo "Found existing provider with PK: $PROVIDER_PK, updating..."
                  PROVIDER_UPDATE_DATA="{
                    \"external_host\": \"${external_host}\",
                    \"internal_host\": \"${internal_host}\",
                    \"internal_host_ssl_validation\": {{ .Values.proxyProvider.internalHostSslValidation }},
                    \"mode\": \"${PROXY_MODE}\",
                    \"cookie_domain\": \"${COOKIE_DOMAIN}\",
                    \"skip_path_regex\": \"${SKIP_PATH_REGEX}\",
                    \"basic_auth_enabled\": {{ .Values.proxyProvider.basicAuthEnabled }}
                  }"
                  
                  if retry_api_call "${AUTHENTIK_HOST}/api/v3/providers/proxy/${PROVIDER_PK}/" "PATCH" "$PROVIDER_UPDATE_DATA"; then
                    echo "✓ Updated $service_key proxy provider"
                  else
                    echo "✗ Failed to update $service_key proxy provider"
                    return 1
                  fi
                else
                  echo "Provider not found, creating new one..."
                  PROVIDER_DATA="{
                    \"name\": \"${service_key}-proxy\",
                    \"authorization_flow\": \"${AUTH_FLOW_UUID}\",
                    \"external_host\": \"${external_host}\",
                    \"internal_host\": \"${internal_host}\",
                    \"internal_host_ssl_validation\": {{ .Values.proxyProvider.internalHostSslValidation }},
                    \"mode\": \"${PROXY_MODE}\",
                    \"cookie_domain\": \"${COOKIE_DOMAIN}\",
                    \"skip_path_regex\": \"${SKIP_PATH_REGEX}\",
                    \"basic_auth_enabled\": {{ .Values.proxyProvider.basicAuthEnabled }},
                    \"basic_auth_password_attribute\": \"\",
                    \"basic_auth_user_attribute\": \"\"
                  }"
                  
                  if retry_api_call "${AUTHENTIK_HOST}/api/v3/providers/proxy/" "POST" "$PROVIDER_DATA"; then
                    PROVIDER_PK=$(cat /tmp/api_response | grep -o '"pk":[0-9]*' | cut -d':' -f2)
                    echo "✓ Created new $service_key proxy provider with PK: $PROVIDER_PK"
                  else
                    echo "✗ Failed to create $service_key proxy provider"
                    return 1
                  fi
                fi
                
                # Get existing application
                echo "Looking for existing $service_key application..."
                if ! retry_api_call "${AUTHENTIK_HOST}/api/v3/core/applications/"; then
                  echo "Failed to check existing applications"
                  return 1
                fi
                
                APP_RESPONSE=$(cat /tmp/api_response)
                APP_PK=$(echo "$APP_RESPONSE" | grep -A10 "\"name\":\"${service_name}\"" | grep -o '"pk":"[^"]*"' | cut -d'"' -f4)
                
                if [ -n "$APP_PK" ]; then
                  echo "Found existing application with PK: $APP_PK, updating..."
                  APP_UPDATE_DATA="{
                    \"provider\": ${PROVIDER_PK},
                    \"meta_description\": \"${description}\",
                    \"meta_publisher\": \"${publisher}\",
                    \"meta_launch_url\": \"${external_host}\"
                  }"
                  
                  if retry_api_call "${AUTHENTIK_HOST}/api/v3/core/applications/${APP_PK}/" "PATCH" "$APP_UPDATE_DATA"; then
                    echo "✓ Updated $service_key application"
                  else
                    echo "✗ Failed to update $service_key application"
                    return 1
                  fi
                else
                  echo "Application not found, creating new one..."
                  APP_DATA="{
                    \"name\": \"${service_name}\",
                    \"slug\": \"${service_slug}\",
                    \"provider\": ${PROVIDER_PK},
                    \"meta_description\": \"${description}\",
                    \"meta_publisher\": \"${publisher}\",
                    \"meta_launch_url\": \"${external_host}\",
                    \"policy_engine_mode\": \"any\",
                    \"group\": \"\"
                  }"
                  
                  if retry_api_call "${AUTHENTIK_HOST}/api/v3/core/applications/" "POST" "$APP_DATA"; then
                    echo "✓ Created new $service_key application"
                  else
                    echo "✗ Failed to create $service_key application"
                    return 1
                  fi
                fi
                
                # Store provider PK for later outpost update
                echo "$PROVIDER_PK" >> /tmp/provider_pks
                echo "✓ $service_key configuration update completed!"
                return 0
              }
              
              # Test authentication
              echo "Testing authentication..."
              if ! retry_api_call "${AUTHENTIK_HOST}/api/v3/core/users/me/"; then
                echo "✗ ERROR: API token authentication failed"
                exit 1
              fi
              echo "✓ Authentication successful"
              
              # Initialize provider PKs file
              echo "" > /tmp/provider_pks
              
              # Update all enabled services
              echo "$SERVICES_JSON" | grep -o '"services":\[[^]]*\]' | sed 's/"services":\[//' | sed 's/\]$//' | sed 's/},{/}\n{/g' | while IFS= read -r service_json; do
                if [ -n "$service_json" ]; then
                  service_key=$(echo "$service_json" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
                  service_name=$(echo "$service_json" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
                  service_slug=$(echo "$service_json" | grep -o '"slug":"[^"]*"' | cut -d'"' -f4)
                  external_host=$(echo "$service_json" | grep -o '"externalHost":"[^"]*"' | cut -d'"' -f4)
                  internal_host=$(echo "$service_json" | grep -o '"internalHost":"[^"]*"' | cut -d'"' -f4)
                  description=$(echo "$service_json" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
                  publisher=$(echo "$service_json" | grep -o '"publisher":"[^"]*"' | cut -d'"' -f4)
                  
                  if ! update_service_config "$service_key" "$service_name" "$service_slug" "$external_host" "$internal_host" "$description" "$publisher"; then
                    echo "✗ Failed to update $service_key configuration"
                    exit 1
                  fi
                fi
              done
              
              # Update the proxy outpost with all current providers
              echo "=== Updating proxy outpost with current providers ==="
              if ! retry_api_call "${AUTHENTIK_HOST}/api/v3/outposts/instances/"; then
                echo "Failed to check existing outposts"
                exit 1
              fi
              
              OUTPOST_RESPONSE=$(cat /tmp/api_response)
              OUTPOST_PK=$(echo "$OUTPOST_RESPONSE" | grep -A10 "\"name\":\"${OUTPOST_NAME}\"" | grep -o '"pk":"[^"]*"' | cut -d'"' -f4)
              
              if [ -n "$OUTPOST_PK" ]; then
                echo "Found proxy outpost with PK: $OUTPOST_PK"
                
                # Get all current provider PKs
                ALL_PROVIDER_PKS=$(cat /tmp/provider_pks | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
                
                if [ -n "$ALL_PROVIDER_PKS" ]; then
                  FINAL_PROVIDERS="[$ALL_PROVIDER_PKS]"
                  UPDATE_DATA="{\"providers\": $FINAL_PROVIDERS}"
                  
                  if retry_api_call "${AUTHENTIK_HOST}/api/v3/outposts/instances/${OUTPOST_PK}/" "PATCH" "$UPDATE_DATA"; then
                    echo "✓ Updated proxy outpost with current providers!"
                  else
                    echo "✗ Failed to update proxy outpost"
                    exit 1
                  fi
                else
                  echo "No providers to update in outpost"
                fi
              else
                echo "✗ Proxy outpost '${OUTPOST_NAME}' not found"
                exit 1
              fi
              
              echo "=== All services proxy configuration update completed successfully! ==="
      volumes:
        - name: service-config
          configMap:
            name: {{ include "authentik-proxy-config.fullname" . }}-service-config