# Authentik Token Management Quick Reference

## Emergency Commands

### Check Token Status

```bash
# List all tokens with expiry information
mise run list-tokens

# Check specific token
python scripts/token-management/authentik_token_manager.py validate --token <token>
```

### Force Token Rotation

```bash
# Immediate rotation
mise run rotate-tokens

# Dry run first
python scripts/token-management/authentik_token_manager.py rotate --dry-run
```

### Manual Token Creation

```bash
# Create new 1-year token
mise run create-token

# Force creation even if valid tokens exist
python scripts/token-management/authentik_token_manager.py create --force
```

## Troubleshooting

### Authentication Failures

1. Check token expiry: `mise run list-tokens`
2. Check External Secret sync: `kubectl get externalsecret -n authentik`
3. Check 1Password connectivity: `kubectl logs -n onepassword-connect deployment/onepassword-connect`

### Job Failures

```bash
# Check rotation job logs
kubectl logs -n authentik -l app.kubernetes.io/name=authentik-token-rotation

# Check health check logs
kubectl logs -n authentik -l app.kubernetes.io/name=authentik-token-health-check

# Check enhanced setup job logs
kubectl logs -n authentik job/authentik-enhanced-token-setup
```

### Manual Recovery

```bash
# Get Authentik pod
AUTHENTIK_POD=$(kubectl get pods -n authentik -l app.kubernetes.io/component=server -o jsonpath='{.items[0].metadata.name}')

# Create emergency token
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

# Update 1Password
op item edit "Authentik Admin Token" --vault=homelab token="<new_token>"
```

## Monitoring

### Key Alerts

- `AuthentikTokenRotationJobFailed`: Critical - rotation failed
- `AuthentikTokenRotationJobNotRun`: Warning - no rotation in 2+ days
- `AuthentikTokenSecretMissing`: Critical - token secret missing

### Health Checks

```bash
# Check CronJob status
kubectl get cronjobs -n authentik

# Check External Secret status
kubectl get externalsecret authentik-admin-token-enhanced -n authentik

# Check secret contents
kubectl get secret authentik-radius-token -n authentik -o yaml
```

## Configuration

### 1Password Items Required

- `Authentik Admin Token` (homelab vault)
- `Authentik Token Rotation Config` (homelab vault)

### Key Environment Variables

- `ROTATION_ENABLED=true`
- `OVERLAP_DAYS=30`
- `WARNING_DAYS=60`

## File Locations

### Core Components

- Enhanced setup: `infrastructure/authentik-outpost-config/enhanced-token-setup-job.yaml`
- Rotation job: `infrastructure/authentik/token-rotation-cronjob.yaml`
- External secrets: `infrastructure/authentik/external-secret-admin-token-enhanced.yaml`
- Monitoring: `infrastructure/authentik/token-monitoring-simple.yaml`

### Scripts

- Token manager: `scripts/token-management/authentik_token_manager.py`
- Tests: `scripts/token-management/test_authentik_token_manager.py`
- Requirements: `scripts/token-management/requirements.txt`

### Documentation

- Full guide: `docs/AUTHENTIK_ENHANCED_TOKEN_MANAGEMENT.md`
- This reference: `docs/AUTHENTIK_TOKEN_QUICK_REFERENCE.md`
