# 1Password Connect Setup

This guide provides instructions for setting up 1Password Connect for secure secret management in your Talos Kubernetes cluster.

## Overview

1Password Connect enables secure secret synchronization from 1Password vaults to Kubernetes secrets using the External Secrets Operator. This setup uses a streamlined bootstrap process that automatically handles credential validation and secret creation.

## Prerequisites

- Access to your 1Password account with administrative privileges
- 1Password CLI installed and authenticated (`op signin`)
- `kubectl` access to your Kubernetes cluster
- `OP_ACCOUNT` environment variable set

## 1Password Setup

### Step 1: Create Connect Server

1. Log into your 1Password account at <https://my.1password.com/>
2. Navigate to **Integrations** → **Directory**
3. Find "1Password Connect Server" and click **"Set Up"**
4. Give it a descriptive name: `Kubernetes Cluster - home-ops`
5. Select the vaults to access:
   - **Automation** (for infrastructure secrets)
   - **Services** (for API tokens and service credentials)
6. Click **"Save"** to create the Connect Server

### Step 2: Download Credentials and Token

1. Download the `1password-credentials.json` file (version 2 format)
2. Copy the Connect Token (starts with `eyJ...`)
3. Verify the credentials file contains `"version": "2"` in the JSON structure

### Step 3: Store in 1Password

Create a **"1password connect"** entry in your **Automation vault** with:

- **credentials** field: Upload/paste your `1password-credentials.json` file content
- **token** field: Paste your Connect token

## Vault Structure

### Automation Vault

Infrastructure and cluster secrets:

- `1password connect` - Connect credentials and token
- `BGP Authentication - home-ops` - BGP authentication password
- `Longhorn UI Credentials - home-ops` - Longhorn UI authentication
- `Talos Secrets - home-ops` - Talos cluster secrets

### Services Vault

External service credentials:

- `Cloudflare API Token` - DNS management token
- `Cloudflared homeops kubernetes tunnel` - Tunnel credentials

## Bootstrap Process

The streamlined bootstrap process automatically:

1. Retrieves credentials from your "1password connect" entry
2. Validates the credentials format (ensures version 2)
3. Creates the necessary Kubernetes secrets
4. Validates the created secrets

### Complete Cluster Bootstrap

```bash
# Bootstrap entire cluster (includes 1Password Connect setup)
task bootstrap:cluster
```

### Manual 1Password Connect Bootstrap

```bash
# Bootstrap just 1Password Connect secrets
task bootstrap:1password-secrets

# Validate 1Password Connect secrets
task bootstrap:validate-1password-secrets
```

## Validation

After bootstrap, validate the setup:

```bash
# Simple validation of created secrets
task bootstrap:validate-1password-secrets

# Check if 1Password Connect deployment is ready
kubectl get deployment -n onepassword-connect onepassword-connect

# Test API connectivity (after deployment)
kubectl port-forward -n onepassword-connect svc/onepassword-connect 8080:8080 &
curl -H "Authorization: Bearer $(kubectl get secret -n onepassword-connect onepassword-connect-token -o jsonpath='{.data.token}' | base64 -d)" http://localhost:8080/v1/health
```

## Troubleshooting

### Common Issues

#### "credentials file is not version 2"

- **Cause**: Using old version 1 credentials
- **Solution**: Generate new version 2 credentials from 1Password web interface

#### "failed to FindCredentialsUniqueKey"

- **Cause**: Corrupted or incomplete credentials file
- **Solution**: Re-download credentials file from 1Password web interface

#### "connection timeout" or "connection refused"

- **Cause**: 1Password Connect service not running or misconfigured
- **Solution**: Check deployment status and restart if needed

#### ExternalSecret shows "SecretSyncError"

- **Cause**: Item name mismatch or missing vault access
- **Solution**: Verify item names match exactly and vault permissions are correct

### Validation Commands

```bash
# Check 1Password Connect pod logs
kubectl logs -n onepassword-connect deployment/onepassword-connect

# Check External Secrets Operator logs
kubectl logs -n external-secrets-system deployment/external-secrets

# List all external secrets and their status
kubectl get externalsecrets -A

# Check specific external secret details
kubectl describe externalsecret -n NAMESPACE SECRET_NAME
```

## Security Notes

- Keep the `1password-credentials.json` file secure
- Don't commit credentials to Git
- Rotate Connect tokens periodically
- Use least-privilege vault access
- Monitor External Secrets for unauthorized access attempts

## Next Steps After Setup

1. **Deploy 1Password Connect**:

   ```bash
   kubectl apply -k infrastructure/onepassword-connect/
   ```

2. **Wait for deployment**:

   ```bash
   kubectl rollout status deployment -n onepassword-connect onepassword-connect
   ```

3. **Deploy External Secrets Operator**:

   ```bash
   kubectl apply -k infrastructure/external-secrets/
   ```

4. **Verify External Secrets sync**:
   ```bash
   kubectl get externalsecrets -A
   ```

---

**Cluster**: home-ops
**1Password Vaults**: Automation, Services
