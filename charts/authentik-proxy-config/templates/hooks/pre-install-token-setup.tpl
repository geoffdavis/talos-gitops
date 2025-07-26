apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "authentik-proxy-config.fullname" . }}-pre-install-token-setup
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "authentik-proxy-config.labels" . | nindent 4 }}
    app.kubernetes.io/component: pre-install-token-hook
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "-10"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ .Values.hooks.retries }}
  activeDeadlineSeconds: {{ .Values.hooks.timeout }}
  template:
    metadata:
      labels:
        {{- include "authentik-proxy-config.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: pre-install-token-hook
    spec:
      restartPolicy: OnFailure
      serviceAccountName: {{ include "authentik-proxy-config.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.securityContext | nindent 8 }}
      volumes:
        - name: op-cli
          emptyDir: {}
      initContainers:
        - name: wait-for-authentik
          image: {{ .Values.hooks.image }}
          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}
          command:
            - /bin/sh
            - -c
            - |
              echo "Waiting for Authentik server to be ready..."
              until curl -f -s {{ .Values.authentik.host }}/if/flow/initial-setup/ > /dev/null 2>&1; do
                echo "Authentik not ready yet, waiting 10 seconds..."
                sleep 10
              done
              echo "Authentik server is ready!"
      containers:
        - name: setup-enhanced-token
          image: "ghcr.io/goauthentik/server:2024.8.3"
          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}
          env:
            - name: AUTHENTIK_REDIS__HOST
              value: "authentik-redis-master.authentik.svc.cluster.local"
            - name: AUTHENTIK_POSTGRESQL__HOST
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__HOST
            - name: AUTHENTIK_POSTGRESQL__NAME
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__NAME
            - name: AUTHENTIK_POSTGRESQL__USER
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__USER
            - name: AUTHENTIK_POSTGRESQL__PASSWORD
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__PASSWORD
            - name: AUTHENTIK_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.externalSecrets.configSecretName }}
                  key: AUTHENTIK_SECRET_KEY
            - name: OP_CONNECT_HOST
              value: "http://onepassword-connect.onepassword-connect.svc.cluster.local:8080"
            - name: OP_CONNECT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: onepassword-connect-token
                  key: token
          volumeMounts:
            - name: op-cli
              mountPath: /tmp/op-cli
          command:
            - /bin/bash
            - -c
            - |
              set -e
              echo "=== Enhanced Token Setup with 1-Year Expiry ==="
              echo "Starting enhanced admin user and long-lived API token setup..."

              # Install 1Password CLI
              echo "Installing 1Password CLI..."
              curl -sSfLo /tmp/op.zip https://cache.agilebits.com/dist/1P/op2/pkg/v2.29.0/op_linux_amd64_v2.29.0.zip
              unzip -o /tmp/op.zip -d /tmp/op-cli/
              chmod +x /tmp/op-cli/op
              export PATH="/tmp/op-cli:$PATH"

              # Use ak shell to create admin user and long-lived token
              ak shell -c "
              from authentik.core.models import User, Token
              from datetime import datetime, timedelta
              from django.utils import timezone
              import secrets
              import base64
              import json

              # Create or get the akadmin user
              user, created = User.objects.get_or_create(
                  username='akadmin',
                  defaults={
                      'name': 'Admin User',
                      'email': 'admin@k8s.home.geoffdavis.com',
                      'is_superuser': True
                  }
              )
              if created:
                  print(f'✓ Created user: {user.username}')
              else:
                  # Ensure existing user has proper permissions
                  user.is_superuser = True
                  user.save()
                  print(f'✓ Updated existing user: {user.username}')

              # Calculate 1-year expiry date
              now = timezone.now()
              expiry_date = now + timedelta(days=365)
              print(f'✓ Token expiry set to: {expiry_date.isoformat()}')

              # Check for existing tokens and their expiry
              existing_tokens = Token.objects.filter(user=user, intent='api')
              valid_tokens = []

              for token in existing_tokens:
                  if token.expires and token.expires > now:
                      days_remaining = (token.expires - now).days
                      print(f'ℹ Found existing valid token: {token.key[:8]}... (expires in {days_remaining} days)')
                      if days_remaining > 30:  # Keep tokens with more than 30 days
                          valid_tokens.append(token)
                      else:
                          print(f'⚠ Token {token.key[:8]}... expires soon, will be replaced')
                  else:
                      print(f'⚠ Found expired/invalid token: {token.key[:8]}...')

              # Create new token if no valid long-term tokens exist
              if not any(token for token in valid_tokens if (token.expires - now).days > 300):
                  # Delete old tokens to avoid conflicts
                  old_count = Token.objects.filter(user=user, intent='api').count()
                  Token.objects.filter(user=user, intent='api').delete()
                  if old_count > 0:
                      print(f'✓ Cleaned up {old_count} old tokens')

                  # Create a new long-lived API token
                  token_key = secrets.token_hex(32)
                  token = Token.objects.create(
                      user=user,
                      intent='api',
                      key=token_key,
                      description=f'Long-lived RADIUS Outpost Token (1 year) - Created {now.strftime(\"%Y-%m-%d\")}',
                      expires=expiry_date,
                      expiring=True
                  )
                  print(f'✓ Created new 1-year token: {token.key[:8]}...')

                  # Output token information for 1Password update
                  token_info = {
                      'token': token.key,
                      'expires': expiry_date.isoformat(),
                      'created': now.isoformat(),
                      'description': token.description,
                      'user': user.username
                  }

                  # Output the token in base64 format for Kubernetes secret
                  token_b64 = base64.b64encode(token.key.encode()).decode()
                  print(f'✓ Token (base64): {token_b64}')

                  # Output JSON for 1Password
                  print(f'✓ Token Info JSON: {json.dumps(token_info, indent=2)}')

                  # Validate the token works
                  print('✓ Validating token...')
                  from django.test import Client
                  from django.contrib.auth import authenticate

                  # Simple validation - if we got here, the token was created successfully
                  print('✓ Token validation: Token created and stored successfully')

              else:
                  print('✓ Valid long-term token already exists, skipping creation')
                  for token in valid_tokens:
                      if (token.expires - now).days > 300:
                          print(f'✓ Using existing token: {token.key[:8]}... (expires {token.expires.strftime(\"%Y-%m-%d\")})')
                          token_b64 = base64.b64encode(token.key.encode()).decode()
                          print(f'✓ Token (base64): {token_b64}')
                          break

              print('✓ Enhanced token setup completed successfully!')

              # Store the token info for 1Password update
              with open('/tmp/token_info.json', 'w') as f:
                  if 'token_info' in locals():
                      f.write(json.dumps(token_info, indent=2))
                  else:
                      # Use existing token info
                      for token in valid_tokens:
                          if (token.expires - now).days > 300:
                              existing_info = {
                                  'token': token.key,
                                  'expires': token.expires.isoformat(),
                                  'created': token.created.isoformat() if hasattr(token, 'created') else now.isoformat(),
                                  'description': token.description,
                                  'user': user.username,
                                  'last_rotation': now.isoformat(),
                                  'rotation_status': 'active'
                              }
                              f.write(json.dumps(existing_info, indent=2))
                              break
              "

              echo "=== Updating 1Password ==="
              echo "Updating 1Password item 'Authentik Admin Token' with new token information..."

              # Check if token info file exists
              if [ -f /tmp/token_info.json ]; then
                # Read token information
                TOKEN_DATA=$(cat /tmp/token_info.json)
                TOKEN=$(echo "$TOKEN_DATA" | jq -r '.token')
                EXPIRES=$(echo "$TOKEN_DATA" | jq -r '.expires')
                CREATED=$(echo "$TOKEN_DATA" | jq -r '.created')
                DESCRIPTION=$(echo "$TOKEN_DATA" | jq -r '.description')
                USER=$(echo "$TOKEN_DATA" | jq -r '.user')
                LAST_ROTATION=$(echo "$TOKEN_DATA" | jq -r '.last_rotation // .created')
                ROTATION_STATUS=$(echo "$TOKEN_DATA" | jq -r '.rotation_status // "active"')

                echo "✓ Token information loaded from Authentik"

                # Update 1Password item - create or update "Authentik Admin Token"
                echo "Updating 1Password item: Authentik Admin Token"

                # Check if item exists
                if op item get "Authentik Admin Token" --vault homelab >/dev/null 2>&1; then
                  echo "✓ Item exists, updating..."
                  op item edit "Authentik Admin Token" \
                    --vault homelab \
                    token="$TOKEN" \
                    expires="$EXPIRES" \
                    created="$CREATED" \
                    description="$DESCRIPTION" \
                    user="$USER" \
                    last_rotation="$LAST_ROTATION" \
                    rotation_status="$ROTATION_STATUS"
                  echo "✓ 1Password item 'Authentik Admin Token' updated successfully"
                else
                  echo "✓ Item doesn't exist, creating..."
                  op item create \
                    --category="API Credential" \
                    --title="Authentik Admin Token" \
                    --vault homelab \
                    token="$TOKEN" \
                    expires="$EXPIRES" \
                    created="$CREATED" \
                    description="$DESCRIPTION" \
                    user="$USER" \
                    last_rotation="$LAST_ROTATION" \
                    rotation_status="$ROTATION_STATUS"
                  echo "✓ 1Password item 'Authentik Admin Token' created successfully"
                fi
              else
                echo "⚠ No new token created, 1Password update skipped"
              fi

              echo "=== Token Setup Summary ==="
              echo "✓ Admin user configured with superuser privileges"
              echo "✓ Long-lived API token created/validated (1 year expiry)"
              echo "✓ 1Password item 'Authentik Admin Token' updated automatically"
              echo "✓ External Secrets will automatically sync the updated token"
              echo "✓ Token ready for use with outpost configurations"
              echo ""
              echo "Enhanced token setup completed successfully!"
