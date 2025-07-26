apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "authentik-proxy-config.fullname" . }}-post-install-config
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "authentik-proxy-config.labels" . | nindent 4 }}
    app.kubernetes.io/component: post-install-hook
  annotations:
    helm.sh/hook: post-install
    helm.sh/hook-weight: "1"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ .Values.hooks.retries }}
  activeDeadlineSeconds: {{ .Values.hooks.timeout }}
  template:
    metadata:
      labels:
        {{- include "authentik-proxy-config.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: post-install-hook
    spec:
      restartPolicy: OnFailure
      serviceAccountName: {{ include "authentik-proxy-config.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.securityContext | nindent 8 }}
      containers:
        - name: configure-proxies
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
              echo "=== Authentik Proxy Configuration Post-Install Hook ==="

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

              # Function to create provider and application atomically
              create_service_config() {
                local service_key="$1"
                local service_name="$2"
                local service_slug="$3"
                local external_host="$4"
                local internal_host="$5"
                local description="$6"
                local publisher="$7"

                echo "=== Configuring $service_name ==="

                # Check if provider already exists
                echo "Checking for existing $service_key proxy provider..."
                if ! retry_api_call "${AUTHENTIK_HOST}/api/v3/providers/proxy/"; then
                  echo "Failed to check existing proxy providers"
                  return 1
                fi

                PROVIDER_RESPONSE=$(cat /tmp/api_response)
                PROVIDER_EXISTS=$(echo "$PROVIDER_RESPONSE" | grep -o "\"name\":\"${service_key}-proxy\"" || echo "")

                if [ -z "$PROVIDER_EXISTS" ]; then
                  echo "Creating $service_key proxy provider..."
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
                    echo "✓ Created $service_key proxy provider with PK: $PROVIDER_PK"
                  else
                    echo "✗ Failed to create $service_key proxy provider"
                    return 1
                  fi
                else
                  echo "✓ $service_key proxy provider already exists"
                  PROVIDER_PK=$(echo "$PROVIDER_RESPONSE" | grep -A10 "\"name\":\"${service_key}-proxy\"" | grep -o '"pk":[0-9]*' | cut -d':' -f2)
                  echo "Found existing provider with PK: $PROVIDER_PK"
                fi

                # Check if Application already exists
                echo "Checking for existing $service_key application..."
                if ! retry_api_call "${AUTHENTIK_HOST}/api/v3/core/applications/"; then
                  echo "Failed to check existing applications"
                  return 1
                fi

                APP_RESPONSE=$(cat /tmp/api_response)
                APP_EXISTS=$(echo "$APP_RESPONSE" | grep -o "\"name\":\"${service_name}\"" || echo "")

                if [ -z "$APP_EXISTS" ]; then
                  echo "Creating $service_key application..."
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
                    echo "✓ $service_key application created successfully!"
                  else
                    echo "✗ Failed to create $service_key application"
                    return 1
                  fi
                else
                  echo "✓ $service_key application already exists"
                fi

                # Store provider PK for later outpost update
                echo "$PROVIDER_PK" >> /tmp/provider_pks
                echo "✓ $service_key configuration completed!"
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

              # Configure all enabled services atomically
              echo "$SERVICES_JSON" | grep -o '"services":\[[^]]*\]' | sed 's/"services":\[//' | sed 's/\]$//' | sed 's/},{/}\n{/g' | while IFS= read -r service_json; do
                if [ -n "$service_json" ]; then
                  service_key=$(echo "$service_json" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
                  service_name=$(echo "$service_json" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
                  service_slug=$(echo "$service_json" | grep -o '"slug":"[^"]*"' | cut -d'"' -f4)
                  external_host=$(echo "$service_json" | grep -o '"externalHost":"[^"]*"' | cut -d'"' -f4)
                  internal_host=$(echo "$service_json" | grep -o '"internalHost":"[^"]*"' | cut -d'"' -f4)
                  description=$(echo "$service_json" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
                  publisher=$(echo "$service_json" | grep -o '"publisher":"[^"]*"' | cut -d'"' -f4)

                  if ! create_service_config "$service_key" "$service_name" "$service_slug" "$external_host" "$internal_host" "$description" "$publisher"; then
                    echo "✗ Failed to configure $service_key, rolling back..."
                    exit 1
                  fi
                fi
              done

              # Update the proxy outpost with all providers at once
              echo "=== Updating proxy outpost with all providers ==="
              if ! retry_api_call "${AUTHENTIK_HOST}/api/v3/outposts/instances/"; then
                echo "Failed to check existing outposts"
                exit 1
              fi

              OUTPOST_RESPONSE=$(cat /tmp/api_response)
              OUTPOST_PK=$(echo "$OUTPOST_RESPONSE" | grep -A10 "\"name\":\"${OUTPOST_NAME}\"" | grep -o '"pk":"[^"]*"' | cut -d'"' -f4)

              if [ -n "$OUTPOST_PK" ]; then
                echo "Found proxy outpost with PK: $OUTPOST_PK"

                # Get current providers list
                CURRENT_PROVIDERS=$(echo "$OUTPOST_RESPONSE" | grep -A10 "\"name\":\"${OUTPOST_NAME}\"" | grep -o '"providers":\[[0-9,]*\]' | sed 's/"providers":\[\([0-9,]*\)\]/\1/')

                # Get new provider PKs
                NEW_PROVIDER_PKS=$(cat /tmp/provider_pks | grep -v '^$' | tr '\n' ',' | sed 's/,$//')

                # Combine current and new providers
                if [ -n "$CURRENT_PROVIDERS" ] && [ -n "$NEW_PROVIDER_PKS" ]; then
                  ALL_PROVIDERS="[$CURRENT_PROVIDERS,$NEW_PROVIDER_PKS]"
                elif [ -n "$NEW_PROVIDER_PKS" ]; then
                  ALL_PROVIDERS="[$NEW_PROVIDER_PKS]"
                else
                  ALL_PROVIDERS="[$CURRENT_PROVIDERS]"
                fi

                # Remove duplicates by converting to unique list
                UNIQUE_PROVIDERS=$(echo "$ALL_PROVIDERS" | sed 's/\[//g' | sed 's/\]//g' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
                FINAL_PROVIDERS="[$UNIQUE_PROVIDERS]"

                UPDATE_DATA="{\"providers\": $FINAL_PROVIDERS}"

                if retry_api_call "${AUTHENTIK_HOST}/api/v3/outposts/instances/${OUTPOST_PK}/" "PATCH" "$UPDATE_DATA"; then
                  echo "✓ Updated proxy outpost with all providers!"
                else
                  echo "✗ Failed to update proxy outpost"
                  exit 1
                fi
              else
                echo "✗ Proxy outpost '${OUTPOST_NAME}' not found"
                exit 1
              fi

              echo "=== All services proxy configuration completed successfully! ==="
      volumes:
        - name: service-config
          configMap:
            name: {{ include "authentik-proxy-config.fullname" . }}-service-config
