# Authentik Enhanced Token Management System

This document describes the enhanced token management system for Authentik that resolves the 25-minute token expiry issue and provides automated token lifecycle management.

## Overview

The enhanced token management system provides:

- **Long-lived tokens**: 1-year expiry instead of 25 minutes
- **Automated rotation**: Seamless token rotation with overlap periods
- **Monitoring & alerting**: Comprehensive monitoring of token health
- **1Password integration**: Secure token storage and automated updates
- **Python-based tooling**: Robust, testable token management scripts

## Architecture

### Components

1. **Enhanced Token Setup Job** ([`enhanced-token-setup-job.yaml`](../infrastructure/authentik-outpost-config/enhanced-token-setup-job.yaml))
   - Creates 1-year tokens with proper expiry management
   - Validates existing tokens and prevents unnecessary recreation
   - Provides detailed logging and status reporting

2. **Token Management Scripts** ([`scripts/token-management/`](../scripts/token-management/))
   - Python-based token management with shared logic
   - Unit tests for reliability
   - CLI interface for manual operations

3. **Enhanced External Secrets** ([`external-secret-admin-token-enhanced.yaml`](../infrastructure/authentik/external-secret-admin-token-enhanced.yaml))
   - Supports token rotation metadata
   - Multiple token entries for overlap periods
   - Automated sync with 1Password

4. **Token Rotation CronJob** ([`token-rotation-cronjob.yaml`](../infrastructure/authentik/token-rotation-cronjob.yaml))
   - Daily automated token health checks
   - Automatic rotation when tokens approach expiry
   - Notification integration for status updates

5. **Monitoring & Alerting** ([`token-monitoring-simple.yaml`](../infrastructure/authentik/token-monitoring-simple.yaml))
   - Prometheus alerts for token expiry
   - Health check monitoring
   - Job failure detection

## Token Lifecycle

### Creation

1. **Enhanced Token Setup Job** runs during deployment
2. Checks for existing valid long-term tokens
3. Creates new 1-year token if needed
4. Outputs token information for 1Password update

### Rotation

1. **Daily Health Check** (2 AM UTC) evaluates token status
2. **30-day overlap period** ensures seamless transitions
3. **Automatic rotation** when tokens expire within overlap period
4. **Validation** ensures new tokens work before completing rotation

### Token Monitoring

1. **Prometheus alerts** for token expiry warnings (60 days, 30 days)
2. **Job failure alerts** for rotation and health check failures
3. **External secret sync monitoring** for 1Password integration
4. **Token validation health checks** every 6 hours

## Configuration

### 1Password Setup

Create the following items in your 1Password vault:

#### Authentik Admin Token

```text
Vault: homelab
Item: Authentik Admin Token
Fields:
  - token: [64-character hex token]
  - expires: [ISO 8601 timestamp]
  - created: [ISO 8601 timestamp]
  - description: [token description]
  - last_rotation: [ISO 8601 timestamp]
  - rotation_status: active
```

#### Token Rotation Config

```text
Vault: homelab
Item: Authentik Token Rotation Config
Fields:
  - rotation_enabled: true
  - overlap_days: 30
  - check_interval: 24h
  - warning_days: 60
  - onepassword_vault: homelab
  - onepassword_item: Authentik Admin Token
  - notification_enabled: true
  - notification_webhook: [optional webhook URL]
  - validation_enabled: true
  - validation_timeout: 30s
```

### Environment Variables

The token management system uses the following environment variables:

| Variable               | Default     | Description                   |
| ---------------------- | ----------- | ----------------------------- |
| `NAMESPACE`            | `authentik` | Kubernetes namespace          |
| `ROTATION_ENABLED`     | `true`      | Enable automatic rotation     |
| `OVERLAP_DAYS`         | `30`        | Overlap period for rotation   |
| `WARNING_DAYS`         | `60`        | Warning threshold in days     |
| `VALIDATION_ENABLED`   | `true`      | Enable token validation       |
| `NOTIFICATION_ENABLED` | `true`      | Enable notifications          |
| `NOTIFICATION_WEBHOOK` | -           | Webhook URL for notifications |

## Usage

### Manual Token Operations

The Python-based token manager provides several CLI commands:

```bash
# Install dependencies
mise run install-token-deps

# Create a new long-lived token
mise run create-token

# Validate an existing token
python scripts/token-management/authentik_token_manager.py validate --token <token>

# List all tokens with status
mise run list-tokens

# Force token rotation
mise run rotate-tokens

# Run tests
mise run test-token-manager
```

### Token Creation

```bash
# Create token with default 365-day expiry
python scripts/token-management/authentik_token_manager.py create

# Create token with custom expiry
python scripts/token-management/authentik_token_manager.py create --expiry-days 180

# Force creation even if valid tokens exist
python scripts/token-management/authentik_token_manager.py create --force
```

### Token Validation

```bash
# Validate a specific token
python scripts/token-management/authentik_token_manager.py validate --token <token>

# List all tokens with health status
python scripts/token-management/authentik_token_manager.py list --json
```

### Token Rotation

```bash
# Check if rotation is needed and rotate if necessary
python scripts/token-management/authentik_token_manager.py rotate

# Dry run to see what would happen
python scripts/token-management/authentik_token_manager.py rotate --dry-run

# Custom overlap period
python scripts/token-management/authentik_token_manager.py rotate --overlap-days 45
```

## Monitoring

### Prometheus Alerts

The system provides the following alerts:

| Alert                               | Severity | Description                        |
| ----------------------------------- | -------- | ---------------------------------- |
| `AuthentikTokenRotationJobFailed`   | Critical | Token rotation job failed          |
| `AuthentikTokenRotationJobNotRun`   | Warning  | Rotation job hasn't run in 2+ days |
| `AuthentikTokenSecretMissing`       | Critical | Token secret is missing            |
| `AuthentikExternalSecretNotSynced`  | Warning  | External secret sync errors        |
| `AuthentikTokenConfigSecretMissing` | Warning  | Rotation config secret missing     |

### Health Checks

- **Token validation**: Every 6 hours via health check CronJob
- **Rotation status**: Daily via rotation CronJob
- **External secret sync**: Continuous via External Secrets Operator
- **Job monitoring**: Via Prometheus job metrics

## Troubleshooting

### Common Issues

#### Token Expiry Errors

**Symptoms**: Authentication failures, 403 errors in outpost jobs

**Solution**:

1. Check token status: `mise run list-tokens`
2. Force rotation if needed: `mise run rotate-tokens`
3. Verify 1Password sync: Check External Secrets logs

#### Rotation Job Failures

**Symptoms**: Prometheus alerts, failed CronJob pods

**Solution**:

1. Check job logs: `kubectl logs -n authentik job/authentik-token-rotation-<timestamp>`
2. Verify RBAC permissions
3. Check Authentik server connectivity
4. Validate 1Password credentials

#### External Secret Sync Issues

**Symptoms**: Secret not updating, sync errors in logs

**Solution**:

1. Check External Secrets Operator logs
2. Verify 1Password Connect connectivity
3. Validate vault and item names
4. Check ClusterSecretStore configuration

### Manual Recovery

If automated systems fail, you can manually recover:

1. **Create emergency token**:

   ```bash
   # Get Authentik pod
   AUTHENTIK_POD=$(kubectl get pods -n authentik -l app.kubernetes.io/component=server -o jsonpath='{.items[0].metadata.name}')

   # Create token manually
   kubectl exec -n authentik $AUTHENTIK_POD -- ak shell -c "
   from authentik.core.models import User, Token
   from datetime import datetime, timedelta
   import secrets

   user = User.objects.get(username='akadmin')
   token_key = secrets.token_hex(32)
   token = Token.objects.create(
       user=user,
       intent='api',
       key=token_key,
       description='Emergency token - $(date)',
       expires=datetime.now() + timedelta(days=365),
       expiring=True
   )
   print(f'Emergency token: {token.key}')
   "
   ```

2. **Update 1Password manually**:

   ```bash
   op item edit "Authentik Admin Token" --vault=homelab token="<new_token>"
   ```

3. **Force External Secret sync**:

   ```bash
   kubectl annotate externalsecret authentik-admin-token-enhanced -n authentik \
     force-sync="$(date +%s)"
   ```

## Security Considerations

### Token Security

- **Minimal Permissions**: Tokens have only required API permissions
- **Encrypted Storage**: All tokens stored encrypted in 1Password
- **Access Logging**: All token operations are logged
- **Rotation Tracking**: Complete audit trail of token changes

### Operational Security

- **Automated Rotation**: Reduces manual intervention and human error
- **Overlap Periods**: Prevents service disruption during rotation
- **Validation Checks**: Ensures new tokens work before rotation
- **Fallback Mechanisms**: Multiple recovery options available

### Network Security

- **Internal Communication**: All API calls use cluster-internal networking
- **TLS Encryption**: External communications use TLS
- **RBAC Controls**: Strict Kubernetes RBAC permissions
- **Secret Management**: Kubernetes secrets with proper access controls

## Migration from Legacy System

### Pre-Migration Checklist

1. **Backup current tokens**: Export existing token information
2. **Verify 1Password setup**: Ensure proper vault and item configuration
3. **Test External Secrets**: Validate 1Password Connect integration
4. **Review monitoring**: Ensure Prometheus and alerting are configured

### Migration Steps

1. **Deploy enhanced components**:

   ```bash
   flux reconcile kustomization infrastructure-authentik -n flux-system
   ```

2. **Verify enhanced token creation**:

   ```bash
   kubectl logs -n authentik job/authentik-enhanced-token-setup
   ```

3. **Update 1Password with new token**:
   - Copy token from job logs
   - Update 1Password item
   - Verify External Secret sync

4. **Test token functionality**:

   ```bash
   mise run validate-token --token <new_token>
   ```

5. **Monitor for issues**:
   - Check outpost job logs
   - Verify authentication flows
   - Monitor Prometheus alerts

### Rollback Plan

If issues occur, you can rollback by:

1. **Disable enhanced components**:

   ```bash
   # Comment out enhanced components in kustomization.yaml
   flux reconcile kustomization infrastructure-authentik -n flux-system
   ```

2. **Restore legacy token**:

   ```bash
   # Use legacy admin-token-setup-job.yaml
   kubectl apply -f infrastructure/authentik-outpost-config/admin-token-setup-job.yaml
   ```

3. **Update 1Password with legacy token**:
   - Run legacy job to get token
   - Update 1Password manually

## Future Enhancements

### Planned Improvements

1. **Multi-token support**: Support for multiple active tokens
2. **Custom rotation schedules**: Per-token rotation policies
3. **Advanced monitoring**: Custom metrics and dashboards
4. **Integration testing**: Automated end-to-end tests
5. **Backup tokens**: Emergency token generation

### Contributing

To contribute improvements:

1. **Test changes**: Run unit tests and integration tests
2. **Update documentation**: Keep this guide current
3. **Monitor impact**: Verify changes don't break existing functionality
4. **Security review**: Ensure changes maintain security posture

## References

- [Authentik API Documentation](https://docs.goauthentik.io/developer-docs/api/)
- [External Secrets Operator](https://external-secrets.io/)
- [1Password Connect](https://developer.1password.com/docs/connect/)
- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/)
- [Kubernetes CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
