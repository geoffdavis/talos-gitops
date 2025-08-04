# Grafana OIDC Migration Guide

This guide documents the migration of Grafana from proxy-based authentication to native OIDC authentication with Authentik.

## Overview

**Migration Goal**: Replace proxy-based authentication with native Grafana OIDC integration to reduce complexity and improve performance.

**Benefits**:

- Direct authentication without proxy overhead
- Better user experience with native Grafana login flow
- Reduced attack surface by removing proxy layer
- Simplified configuration and maintenance

## Prerequisites

1. Authentik server operational at `https://authentik.k8s.home.geoffdavis.com`
2. 1Password Connect configured for secret management
3. Monitoring stack deployed and operational

## Deployment Steps

### Step 1: Create OIDC Application in Authentik

```bash
# Apply the OIDC setup job
kubectl apply -f infrastructure/authentik-outpost-config/grafana-oidc-setup-job.yaml

# Monitor job execution
kubectl logs -n authentik job/grafana-oidc-setup -f

# Verify job completion
kubectl get job -n authentik grafana-oidc-setup
```

**Expected Output**: Job should complete successfully and create:

- OAuth2/OIDC provider named "Grafana OIDC"
- Application named "Grafana"
- Client ID: `grafana`
- Client secret (displayed in job logs)

### Step 2: Store Client Secret in 1Password

The setup job automatically creates the 1Password entry with cluster-specific naming:

- **Title**: "home-ops-grafana-oidc-client-secret"
- **Field**: "credential" = `<client-secret-from-job>`
- **Tags**: "kubernetes,home-ops,grafana,oidc"

**Note**: The job uses the cluster name "home-ops" as a prefix to prevent conflicts when using a single 1Password vault for multiple clusters.

### Step 3: Deploy Updated Grafana Configuration

```bash
# Apply the updated monitoring configuration
kubectl apply -k infrastructure/monitoring/

# Monitor Grafana pod restart
kubectl rollout status deployment -n monitoring kube-prometheus-stack-grafana

# Verify external secret synchronization
kubectl get externalsecret -n monitoring grafana-oidc-secret
kubectl get secret -n monitoring grafana-oidc-secret
```

### Step 4: Update Proxy Configuration

The proxy configuration has been updated to remove Grafana:

- ConfigMap updated to remove Grafana service
- Service discovery job updated to skip Grafana

```bash
# Apply updated proxy configuration
kubectl apply -k infrastructure/authentik-proxy/

# Restart proxy pods to pick up new configuration
kubectl rollout restart deployment -n authentik-proxy authentik-proxy
```

## Testing and Validation

### Test 1: Direct Grafana Access

1. Navigate to `https://grafana.k8s.home.geoffdavis.com`
2. Should redirect to Authentik login page
3. Login with Authentik credentials
4. Should redirect back to Grafana with authenticated session

### Test 2: OIDC Configuration Validation

```bash
# Check Grafana configuration
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- env | grep GF_AUTH

# Verify ingress configuration
kubectl get ingress -n monitoring

# Check certificate status
kubectl get certificate -n monitoring grafana-tls
```

### Test 3: Role Mapping

The configuration includes role mapping based on Authentik groups:

- `Grafana Admins` group → Grafana Admin role
- `Grafana Editors` group → Grafana Editor role
- Default → Grafana Viewer role

Test by assigning users to different groups in Authentik and verifying their Grafana permissions.

## Configuration Details

### Grafana OIDC Settings

```yaml
env:
  GF_AUTH_GENERIC_OAUTH_ENABLED: "true"
  GF_AUTH_GENERIC_OAUTH_NAME: "Authentik"
  GF_AUTH_GENERIC_OAUTH_CLIENT_ID: "grafana"
  GF_AUTH_GENERIC_OAUTH_SCOPES: "openid profile email"
  GF_AUTH_GENERIC_OAUTH_AUTH_URL: "https://authentik.k8s.home.geoffdavis.com/application/o/authorize/"
  GF_AUTH_GENERIC_OAUTH_TOKEN_URL: "https://authentik.k8s.home.geoffdavis.com/application/o/token/"
  GF_AUTH_GENERIC_OAUTH_API_URL: "https://authentik.k8s.home.geoffdavis.com/application/o/userinfo/"
  GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP: "true"
  GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH: "contains(groups[*], 'Grafana Admins') && 'Admin' || contains(groups[*], 'Grafana Editors') && 'Editor' || 'Viewer'"
```

### Authentik OIDC Provider Settings

- **Client Type**: Confidential
- **Client ID**: `grafana`
- **Redirect URI**: `https://grafana.k8s.home.geoffdavis.com/login/generic_oauth`
- **Scopes**: `openid profile email`
- **Subject Mode**: Hashed User ID
- **Include Claims in ID Token**: Yes

## Rollback Procedures

If issues occur, rollback can be performed:

### Option 1: Revert to Proxy Authentication

1. **Revert Grafana Configuration**:

   ```bash
   # Remove OIDC configuration from prometheus.yaml
   # Remove ingress configuration
   # Restore original LoadBalancer-only service
   ```

2. **Re-enable Proxy Configuration**:

   ```bash
   # Add Grafana back to configmap.yaml
   # Add Grafana back to service-discovery-job.yaml
   ```

3. **Apply Changes**:
   ```bash
   kubectl apply -k infrastructure/monitoring/
   kubectl apply -k infrastructure/authentik-proxy/
   ```

### Option 2: Disable OIDC Temporarily

```bash
# Scale down Grafana to disable OIDC
kubectl scale deployment -n monitoring kube-prometheus-stack-grafana --replicas=0

# Edit configuration to disable OIDC
kubectl patch helmrelease -n monitoring kube-prometheus-stack --type='merge' -p='{"spec":{"values":{"grafana":{"env":{"GF_AUTH_GENERIC_OAUTH_ENABLED":"false"}}}}}'

# Scale back up
kubectl scale deployment -n monitoring kube-prometheus-stack-grafana --replicas=1
```

## Troubleshooting

### Common Issues

1. **OIDC Login Loop**:
   - Check client secret is correct in 1Password
   - Verify redirect URI matches exactly
   - Check Authentik application configuration

2. **Permission Denied**:
   - Verify user is assigned to appropriate Authentik groups
   - Check role mapping configuration
   - Ensure `GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP` is enabled

3. **Certificate Issues**:
   - Verify cert-manager is working
   - Check certificate status: `kubectl get certificate -n monitoring`
   - Ensure ingress TLS configuration is correct

### Debug Commands

```bash
# Check Grafana logs
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana

# Check external secret status
kubectl describe externalsecret -n monitoring grafana-oidc-secret

# Check ingress status
kubectl describe ingress -n monitoring

# Test OIDC endpoints
curl -I https://authentik.k8s.home.geoffdavis.com/application/o/authorize/
curl -I https://authentik.k8s.home.geoffdavis.com/application/o/token/
curl -I https://authentik.k8s.home.geoffdavis.com/application/o/userinfo/
```

## Success Criteria

- ✅ Grafana accessible at `https://grafana.k8s.home.geoffdavis.com`
- ✅ Authentication redirects to Authentik login page
- ✅ Successful login redirects back to Grafana
- ✅ User permissions match Authentik group assignments
- ✅ No proxy-related configuration for Grafana
- ✅ Direct ingress access working with TLS certificates

## Next Steps

After successful Grafana migration:

1. Monitor for any authentication issues
2. Proceed with Dashboard OIDC migration (Phase 1.2)
3. Remove Prometheus from authentication (Phase 1.3)
4. Simplify proxy configuration (Phase 1.4)

This migration reduces the authentication complexity and provides a foundation for the hybrid authentication strategy.
