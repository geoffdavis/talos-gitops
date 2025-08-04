# Grafana OIDC GitOps Automation

This document describes the complete GitOps automation for setting up Grafana OIDC authentication with Authentik.

## Overview

The automation provides a fully GitOps-compliant way to:

1. Create OIDC provider and application in Authentik
2. Store client secrets in 1Password "Automation" vault
3. Sync secrets to Kubernetes via External Secrets
4. Handle existing configurations idempotently

## Components

### 1. RBAC Configuration

**File**: `infrastructure/authentik-outpost-config/rbac.yaml`

- **ServiceAccount**: `authentik-service-account` in `authentik` namespace
- **ClusterRole**: `authentik-outpost-config` with permissions for:
  - External Secrets management
  - Secret creation/updates
  - ConfigMap access
- **ClusterRoleBinding**: Links service account to cluster role

### 2. Grafana OIDC Setup Job

**File**: `infrastructure/authentik-outpost-config/grafana-oidc-setup-job.yaml`

**Features**:

- **Idempotent**: Safely handles existing providers/applications
- **1Password Integration**: Uses "Automation" vault (corrected from "Kubernetes")
- **Error Handling**: Comprehensive error checking and logging
- **Security**: Runs with restricted security context

**Process**:

1. Tests Authentik API connectivity
2. Gets default authorization flow
3. Checks for existing Grafana OIDC provider
4. If exists: Updates 1Password with existing secret
5. If not exists: Creates provider, application, and 1Password entry
6. Provides complete configuration summary

### 3. External Secret Configuration

**File**: `infrastructure/monitoring/grafana-oidc-secret.yaml`

**Features**:

- **Explicit Vault**: Specifies "Automation" vault in remoteRef
- **Auto-sync**: 1-hour refresh interval
- **Template**: Creates properly formatted Kubernetes secret

**Configuration**:

```yaml
data:
  - secretKey: clientSecret
    remoteRef:
      key: "home-ops-grafana-oidc-client-secret"
      property: "credential"
      vault: "Automation" # Explicitly specified
```

### 4. SecretStore Configuration

**File**: `infrastructure/onepassword-connect/secret-store.yaml`

- **ClusterSecretStore**: Available cluster-wide
- **Vault Mapping**: "Automation" vault configured
- **Authentication**: Uses 1Password Connect token

## Usage

### Initial Setup

```bash
# Apply RBAC first
kubectl apply -f infrastructure/authentik-outpost-config/rbac.yaml

# Apply the setup job
kubectl apply -f infrastructure/authentik-outpost-config/grafana-oidc-setup-job.yaml

# Apply external secret
kubectl apply -f infrastructure/monitoring/grafana-oidc-secret.yaml
```

### Monitor Progress

```bash
# Watch job execution
kubectl logs job/grafana-oidc-setup -n authentik -f

# Check external secret sync
kubectl get externalsecret grafana-oidc-secret -n monitoring -w

# Verify final secret
kubectl get secret grafana-oidc-secret -n monitoring
```

### Validation

```bash
# Run validation script
./scripts/validate-grafana-oidc-setup.sh
```

## Idempotency

The automation is designed to be run multiple times safely:

1. **Existing Provider**: If Grafana OIDC provider exists, extracts existing client secret
2. **Existing Application**: Creates application if missing, skips if exists
3. **1Password Entry**: Updates existing entry or creates new one
4. **External Secret**: Syncs regardless of source (existing or new)

## Configuration Details

### Authentik OIDC Provider Settings

- **Client ID**: `grafana`
- **Client Type**: `confidential`
- **Redirect URI**: `https://grafana.k8s.home.geoffdavis.com/login/generic_oauth`
- **Sub Mode**: `hashed_user_id`
- **Include Claims**: `true`
- **Issuer Mode**: `per_provider`

### Authentik Application Settings

- **Name**: `Grafana`
- **Slug**: `grafana`
- **Launch URL**: `https://grafana.k8s.home.geoffdavis.com`
- **Policy Engine**: `any`

### 1Password Entry

- **Title**: `home-ops-grafana-oidc-client-secret`
- **Vault**: `Automation`
- **Category**: `password`
- **Tags**: `kubernetes,home-ops,grafana,oidc`

## Grafana Configuration

After the automation completes, configure Grafana with:

```yaml
grafana:
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      name: Authentik
      client_id: grafana
      client_secret: $__file{/etc/secrets/grafana-oidc-secret/client-secret}
      scopes: openid profile email
      auth_url: https://authentik.k8s.home.geoffdavis.com/application/o/authorize/
      token_url: https://authentik.k8s.home.geoffdavis.com/application/o/token/
      api_url: https://authentik.k8s.home.geoffdavis.com/application/o/userinfo/
      allow_sign_up: true
      auto_login: false
```

## Troubleshooting

### Job Fails with API Connectivity

```bash
# Check Authentik service
kubectl get svc authentik-server -n authentik

# Check admin token
kubectl get secret authentik-admin-token -n authentik
```

### External Secret Not Syncing

```bash
# Check SecretStore
kubectl get secretstore onepassword-connect -n monitoring

# Check 1Password Connect
kubectl get pods -n onepassword-connect

# Force refresh
kubectl annotate externalsecret grafana-oidc-secret -n monitoring force-sync=$(date +%s) --overwrite
```

### 1Password Entry Issues

```bash
# Check if entry exists
op item get "home-ops-grafana-oidc-client-secret" --vault="Automation"

# List vault contents
op item list --vault="Automation"
```

## Security Considerations

1. **Restricted Security Context**: Job runs as non-root with dropped capabilities
2. **Secret Handling**: Client secrets never logged, only length shown
3. **RBAC**: Minimal required permissions for service account
4. **Vault Separation**: Uses dedicated "Automation" vault for operational secrets

## GitOps Principles

This automation follows GitOps principles:

- **Declarative**: All configuration in Git
- **Versioned**: Changes tracked in Git history
- **Immutable**: Jobs create consistent state
- **Automated**: No manual Authentik configuration required
- **Observable**: Comprehensive logging and status reporting

## Integration with Existing Systems

The automation integrates with:

- **Flux**: Deployed via GitOps pipeline
- **External Secrets**: Automatic secret synchronization
- **1Password**: Centralized secret management
- **Authentik**: Identity provider configuration
- **Grafana**: Native OIDC authentication

## Future Enhancements

Potential improvements:

1. **Token Rotation**: Automatic client secret rotation
2. **Multi-Environment**: Support for dev/staging/prod
3. **Backup/Restore**: Configuration backup procedures
4. **Monitoring**: Alerts for authentication failures
