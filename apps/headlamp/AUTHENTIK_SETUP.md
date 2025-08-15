# Headlamp Authentik OIDC Setup

## Authentik Configuration Steps

### 1. Create OAuth2/OIDC Provider

1. Log into Authentik at https://authentik.k8s.home.geoffdavis.com
2. Navigate to **Applications** → **Providers**
3. Click **Create** and select **OAuth2/OpenID Provider**
4. Configure the provider:

```yaml
Name: headlamp-provider
Authentication flow: default-authentication-flow
Authorization flow: default-provider-authorization-implicit-consent

Client type: Confidential
Client ID: headlamp
Client Secret: (Generate a secure secret and save it)

Redirect URIs:
  - https://headlamp.k8s.home.geoffdavis.com/oidc-callback
  - https://headlamp.k8s.home.geoffdavis.com/auth/callback
  - http://localhost:4466/oidc-callback (for local testing)

Scopes:
  - openid
  - profile
  - email
  - groups

Subject mode: Based on the User's Email
Include claims in id_token: ✓ (checked)

Token validity:
  - Access tokens: 3600 seconds
  - Refresh tokens: 2592000 seconds (30 days)
```

### 2. Create Application

1. Navigate to **Applications** → **Applications**
2. Click **Create**
3. Configure:

```yaml
Name: Headlamp
Slug: headlamp
Provider: headlamp-provider (select from dropdown)
Policy engine mode: any
Group: Kubernetes (optional)
Launch URL: https://headlamp.k8s.home.geoffdavis.com
Icon: (optional, upload a Headlamp logo)
```

### 3. Update Group Mappings (Optional)

To pass Kubernetes groups through OIDC:

1. Navigate to **Customization** → **Property Mappings**
2. Create a new **Scope Mapping**:

```python
Name: headlamp-groups
Scope name: groups
Expression:
  return {
    "groups": [f"oidc:{group.name}" for group in user.groups.all()]
  }
```

3. Add this mapping to your provider's scope mappings

### 4. Store Secrets in 1Password

Create a new item in 1Password with:

```yaml
Title: headlamp-oidc
Fields:
  - client_id: headlamp
  - client_secret: <generated-secret-from-authentik>
```

### 5. Deploy Headlamp

```bash
# First, ensure the secret is available
kubectl apply -f apps/headlamp/namespace.yaml
kubectl apply -f apps/headlamp/headlamp-oidc-secret.yaml

# Update the manual secret with actual values (temporary)
kubectl -n headlamp create secret generic headlamp-oidc-manual \
  --from-literal=clientId=headlamp \
  --from-literal=clientSecret='<YOUR-SECRET-HERE>'

# Deploy via Flux
git add apps/headlamp/
git commit -m "feat: add Headlamp with OIDC authentication"
git push

# Force reconciliation
flux reconcile kustomization flux-system --with-source
```

## Testing

### Local Testing (without OIDC)

```bash
# Port-forward for testing
kubectl port-forward -n headlamp svc/headlamp 4466:80

# Access at http://localhost:4466
```

### Production Testing

1. Navigate to https://headlamp.k8s.home.geoffdavis.com
2. Click "Sign in" button
3. You should be redirected to Authentik
4. After authentication, redirected back to Headlamp
5. You should see all cluster resources based on your RBAC permissions

## Troubleshooting

### Check Headlamp logs

```bash
kubectl logs -n headlamp -l app.kubernetes.io/name=headlamp
```

### Verify OIDC configuration

```bash
kubectl describe cm -n headlamp headlamp-config
```

### Common Issues

1. **"Invalid client" error**: Check client ID and secret match Authentik
2. **Redirect URI mismatch**: Ensure callback URLs are exact in Authentik
3. **No resources visible**: Check RBAC bindings for OIDC groups
4. **Token too large**: Already configured larger nginx buffers in ingress

## Group Mapping

Authentik groups are prefixed with `oidc:` in Kubernetes RBAC. Examples:

- Authentik group `admins` → Kubernetes group `oidc:admins`
- Authentik group `developers` → Kubernetes group `oidc:developers`

Update the RBAC bindings in `rbac.yaml` to match your Authentik groups.
