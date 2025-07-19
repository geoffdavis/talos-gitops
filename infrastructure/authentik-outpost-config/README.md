# Authentik RADIUS Outpost Configuration

This directory contains the configuration for automatically setting up a RADIUS outpost in Authentik via API calls.

## Prerequisites

The outpost configuration job requires:
1. A valid Authentik API token to authenticate with the Authentik API
2. Admin credentials stored in 1Password for web interface access

## Initial Setup (One-time)

### 0. Setup Admin Credentials in 1Password

Create an item in your 1Password Services vault named `authentik-admin-credentials` with the following fields:
- `username`: admin
- `password`: [generate a secure password]
- `email`: admin@k8s.home.geoffdavis.com

The admin user will be automatically created by the `authentik-admin-user-setup` job during deployment.

### 1. Create Admin User and API Token

After Authentik is deployed, you need to create an admin user and API token:

```bash
# Get the Authentik server pod name
AUTHENTIK_POD=$(kubectl get pods -n authentik -l app.kubernetes.io/component=server -o jsonpath='{.items[0].metadata.name}')

# Create admin user and API token
kubectl exec -n authentik $AUTHENTIK_POD -- ak shell -c "
from authentik.core.models import User, Token
import secrets

# Create or get the akadmin user
user, created = User.objects.get_or_create(username='akadmin')
if created:
    user.name = 'Admin User'
    user.is_superuser = True
    user.is_staff = True
    user.save()
    print(f'Created user: {user.username}')
else:
    print(f'Found existing user: {user.username}')

# Create an API token for this user
token_key = secrets.token_hex(32)
token, created = Token.objects.get_or_create(
    user=user,
    intent='api',
    defaults={'key': token_key, 'description': 'RADIUS Outpost Configuration Token'}
)
if created:
    print(f'Created new token: {token.key}')
else:
    print(f'Found existing token: {token.key}')
"
```

### 2. Update the Secret

Take the token from the output above and update the Kubernetes secret:

```bash
# Replace <TOKEN> with the actual token from step 1
TOKEN="<TOKEN>"
kubectl patch secret authentik-radius-token -n authentik --type='json' -p='[{"op": "replace", "path": "/data/token", "value": "'$(echo -n "$TOKEN" | base64)'"}]'
```

### 3. Alternative: Update 1Password (Recommended for Production)

For a more secure and repeatable approach, update the token in 1Password:

1. Log into 1Password
2. Find the `authentik-radius-token` item
3. Update the `token` field with the new API token
4. The external-secrets operator will automatically sync the updated token to Kubernetes

## What the Job Does

The outpost configuration job performs the following actions:

1. **Authentication Test**: Verifies the API token works by calling `/api/v3/core/users/me/`
2. **RADIUS Provider**: Creates a RADIUS provider named `radius-provider` if it doesn't exist
3. **RADIUS Outpost**: Creates a RADIUS outpost named `radius-outpost` configured for Kubernetes deployment

## Configuration Details

- **Provider Name**: `radius-provider`
- **Outpost Name**: `radius-outpost`
- **Shared Secret**: `radius-shared-secret-change-me` (should be changed in production)
- **Client Networks**: `0.0.0.0/0,::/0` (allows all clients)
- **Kubernetes Namespace**: `authentik`
- **Service Type**: `LoadBalancer`
- **Replicas**: 2

## Troubleshooting

### Authentication Failures

If the job fails with authentication errors, the token may be invalid or expired. Follow these steps:

1. Check the job logs:
   ```bash
   kubectl logs -n authentik job/authentik-radius-outpost-config
   ```

2. If you see "Authentication failed with status: 403", recreate the token using the steps above.

3. The job includes helpful error messages with the exact commands needed to fix authentication issues.

### Job Stuck or Failed

If the job is stuck or failed:

1. Delete the failed job:
   ```bash
   kubectl delete job authentik-radius-outpost-config -n authentik
   ```

2. Force Flux to reconcile:
   ```bash
   flux reconcile kustomization infrastructure-authentik-outpost-config -n flux-system
   ```

## Security Considerations

- The API token has full admin privileges - store it securely
- Consider rotating the token periodically
- The RADIUS shared secret should be changed from the default value
- Client networks should be restricted to your actual network ranges in production