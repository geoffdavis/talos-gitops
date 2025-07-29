# Cloudflare Tunnel Credential Creation Guide

## Overview

The [`scripts/create-cloudflare-tunnel-credentials.sh`](../scripts/create-cloudflare-tunnel-credentials.sh) script is a targeted tool designed to create only the Cloudflare tunnel credentials needed for deployment. This script is safe to run without affecting any existing credentials or configurations.

## Purpose

This script was created to address scenarios where:

- Only Cloudflare tunnel credentials are missing
- You want to avoid regenerating all credentials
- The tunnel deployment is failing due to missing credentials
- You need to rotate only the Cloudflare tunnel credentials

## Safety Features

✅ **Idempotent Operation**: Safe to run multiple times
✅ **Targeted Scope**: Only affects Cloudflare tunnel credentials
✅ **Existing Check**: Validates if credentials already exist
✅ **Prerequisite Validation**: Ensures all required tools are available
✅ **Error Handling**: Comprehensive error checking and rollback
✅ **No Side Effects**: Does not modify other credentials or configurations

## Prerequisites

Before running the script, ensure you have:

1. **1Password CLI** installed and authenticated:

   ```bash
   op signin
   export OP_ACCOUNT=your-account-name
   ```

2. **mise tool manager** with cloudflared installed:

   ```bash
   mise install cloudflared
   ```

3. **Cloudflare API credentials** configured for cloudflared
4. **Access to the Automation vault** in 1Password

## Usage

### Basic Usage

```bash
# Run the script interactively
./scripts/create-cloudflare-tunnel-credentials.sh
```

### What the Script Does

1. **Prerequisites Check**:
   - Verifies 1Password CLI is installed and authenticated
   - Checks mise and cloudflared availability
   - Validates access to the Automation vault

2. **Existing Credential Check**:
   - Checks if tunnel already exists in Cloudflare
   - Verifies if credentials exist in 1Password
   - Prompts for confirmation if recreating existing resources

3. **Cleanup (if needed)**:
   - Removes old tunnel credentials from 1Password
   - Deletes old tunnel from Cloudflare

4. **Tunnel Creation**:
   - Creates new Cloudflare tunnel: `home-ops-tunnel`
   - Generates fresh tunnel credentials
   - Validates credential file format and size

5. **Credential Storage**:
   - Stores credentials in 1Password as: `Home-ops cloudflare-tunnel.json`
   - Validates successful storage and retrieval

6. **Validation**:
   - Confirms tunnel exists in Cloudflare
   - Tests credential access from 1Password
   - Checks ExternalSecret status (if cluster is available)

## Expected Output

### Successful Execution

```text
==============================================
  Cloudflare Tunnel Credential Creator
==============================================

✓ All prerequisites met
✓ 1Password Connect is accessible
✓ No existing tunnel or credentials found - proceeding with creation
✓ Cleanup completed
✓ Created new Cloudflare tunnel: home-ops-tunnel
✓ Tunnel created with ID: 12345678...
✓ Valid tunnel credentials generated (1234 bytes)
✓ Tunnel credentials stored in 1Password
✓ Credentials successfully stored and retrievable from 1Password
✓ Tunnel is active in Cloudflare
✓ All credential validation checks passed

==============================================
  DNS CONFIGURATION REQUIRED
==============================================

Tunnel ID: 12345678-1234-1234-1234-123456789abc
CNAME Target: 12345678-1234-1234-1234-123456789abc.cfargotunnel.com

Update the following DNS records in Cloudflare:

  grafana.geoffdavis.com  → 12345678-1234-1234-1234-123456789abc.cfargotunnel.com
  prometheus.geoffdavis.com → 12345678-1234-1234-1234-123456789abc.cfargotunnel.com
  longhorn.geoffdavis.com → 12345678-1234-1234-1234-123456789abc.cfargotunnel.com
  k8s.geoffdavis.com → 12345678-1234-1234-1234-123456789abc.cfargotunnel.com
  alerts.geoffdavis.com → 12345678-1234-1234-1234-123456789abc.cfargotunnel.com
  hubble.geoffdavis.com → 12345678-1234-1234-1234-123456789abc.cfargotunnel.com

==============================================
  CLOUDFLARE TUNNEL CREDENTIALS COMPLETE
==============================================

✅ Fresh Cloudflare tunnel created: home-ops-tunnel
✅ Credentials stored in 1Password: Home-ops cloudflare-tunnel.json
✅ Tunnel ID: 12345678...
✅ Ready for Kubernetes deployment
```

## Validation Steps

After running the script, validate the setup:

### 1. Verify 1Password Storage

```bash
# Check if credentials exist in 1Password
op item get "Home-ops cloudflare-tunnel.json" --vault="Automation"
```

### 2. Verify Tunnel in Cloudflare

```bash
# List tunnels to confirm creation
mise exec -- cloudflared tunnel list
```

### 3. Check ExternalSecret (if cluster is running)

```bash
# Check ExternalSecret status
kubectl get externalsecret cloudflare-tunnel-credentials -n cloudflare-tunnel

# Check if secret was created
kubectl get secret cloudflare-tunnel-credentials -n cloudflare-tunnel
```

### 4. Verify Tunnel Deployment Recovery

```bash
# Check tunnel pod status
kubectl get pods -n cloudflare-tunnel

# Check tunnel logs
kubectl logs -n cloudflare-tunnel -l app=cloudflare-tunnel
```

## Troubleshooting

### Common Issues

#### 1. Prerequisites Not Met

**Error**: `1Password CLI (op) is not installed`
**Solution**: Install 1Password CLI and authenticate:

```bash
# Install 1Password CLI (macOS)
brew install 1password-cli

# Authenticate
op signin
export OP_ACCOUNT=your-account-name
```

#### 2. Cloudflared Not Available

**Error**: `cloudflared CLI not available via mise`
**Solution**: Install cloudflared via mise:

```bash
mise install cloudflared
```

#### 3. Cloudflare API Issues

**Error**: `Failed to create new Cloudflare tunnel`
**Solution**: Check Cloudflare API credentials:

```bash
# Verify cloudflared authentication
mise exec -- cloudflared tunnel list
```

#### 4. 1Password Access Issues

**Error**: `Cannot access 'Automation' vault`
**Solution**: Verify 1Password permissions and vault access

#### 5. Existing Resources

**Warning**: `Both tunnel and credentials already exist`
**Action**: Choose whether to recreate or keep existing setup

### Recovery Procedures

#### If Script Fails Mid-Execution

1. **Check what was created**:

   ```bash
   # Check tunnel in Cloudflare
   mise exec -- cloudflared tunnel list

   # Check credentials in 1Password
   op item get "Home-ops cloudflare-tunnel.json" --vault="Automation"
   ```

2. **Clean up partial state**:

   ```bash
   # Delete tunnel if created but credentials failed
   mise exec -- cloudflared tunnel delete home-ops-tunnel --force

   # Remove credentials if stored but tunnel failed
   op item delete "Home-ops cloudflare-tunnel.json" --vault="Automation"
   ```

3. **Re-run the script**:

   ```bash
   ./scripts/create-cloudflare-tunnel-credentials.sh
   ```

## Integration with Deployment

### ExternalSecret Configuration

The script creates credentials that work with the existing ExternalSecret:

```yaml
# infrastructure/cloudflare-tunnel/external-secret.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: cloudflare-tunnel-credentials
  namespace: cloudflare-tunnel
spec:
  data:
    - secretKey: credentials.json
      remoteRef:
        key: "Home-ops cloudflare-tunnel.json" # Created by script
        property: "json"
```

### Tunnel Deployment

The tunnel deployment will automatically recover once credentials are available:

```bash
# Monitor deployment recovery
kubectl get pods -n cloudflare-tunnel -w

# Check tunnel connectivity
kubectl logs -n cloudflare-tunnel -l app=cloudflare-tunnel --tail=50
```

## DNS Configuration

After successful credential creation, update DNS records in Cloudflare:

1. **Log into Cloudflare Dashboard**
2. **Navigate to your domain's DNS settings**
3. **Update CNAME records** to point to the new tunnel:
   - `grafana.geoffdavis.com` → `{tunnel-id}.cfargotunnel.com`
   - `prometheus.geoffdavis.com` → `{tunnel-id}.cfargotunnel.com`
   - `longhorn.geoffdavis.com` → `{tunnel-id}.cfargotunnel.com`
   - `k8s.geoffdavis.com` → `{tunnel-id}.cfargotunnel.com`
   - `alerts.geoffdavis.com` → `{tunnel-id}.cfargotunnel.com`
   - `hubble.geoffdavis.com` → `{tunnel-id}.cfargotunnel.com`

## Security Considerations

- **Credential Rotation**: This script can be used for regular credential rotation
- **Access Control**: Ensure only authorized users can run this script
- **Audit Trail**: All operations are logged with timestamps
- **Cleanup**: Script automatically cleans up temporary files
- **Validation**: Multiple validation steps ensure credential integrity

## Related Documentation

- [1Password Connect Setup](./1PASSWORD_CONNECT_SETUP.md)
- [Bootstrap Troubleshooting](./BOOTSTRAP_TROUBLESHOOTING.md)
- [Operational Workflows](./OPERATIONAL_WORKFLOWS.md)
- [Credential Rotation Process](./CREDENTIAL_ROTATION_PROCESS.md)
