# Credential Rotation Process

This document outlines the complete process for rotating 1Password Connect credentials and generating fresh cluster secrets after a security incident.

## Overview

After the security incident where 1Password Connect credentials were compromised, this process ensures:

1. **Complete credential invalidation** - All old credentials are revoked
2. **Fresh secret generation** - New PKI certificates and cluster secrets
3. **Clean bootstrap** - Cluster starts with entirely new credentials
4. **Secure storage** - All new credentials stored properly in 1Password

## Prerequisites

- Nodes must be in maintenance mode (no cluster configuration)
- 1Password CLI authenticated with proper account access
- `OP_ACCOUNT` environment variable set to `camiandgeoff.1password.com`
- `mise` tool installed and configured

## Quick Start

For immediate credential rotation after security incident:

```bash
# 1. Prepare environment for credential rotation
task onepassword:prepare-credential-rotation

# 2. Bootstrap fresh credentials (revokes old, creates new)
task onepassword:bootstrap-fresh-credentials

# 3. Apply fresh configuration and bootstrap cluster
task bootstrap:phased
```

## Detailed Step-by-Step Process

### Phase 1: Environment Preparation

```bash
# Prepare the environment for credential rotation
task onepassword:prepare-credential-rotation
```

This will:
- ✅ Clean up any local credential files
- ✅ Clear existing Talos generated secrets
- ✅ Verify 1Password entries that need rotation
- ✅ Confirm nodes are in maintenance mode
- ✅ Validate bootstrap process readiness

### Phase 2: Fresh Credential Generation

```bash
# Bootstrap completely fresh credentials
task onepassword:bootstrap-fresh-credentials
```

This will:
- ✅ Revoke old 1Password Connect servers
- ✅ Delete old credential entries from 1Password
- ✅ Create new 1Password Connect server
- ✅ Generate fresh Connect credentials and token
- ✅ Generate fresh Talos cluster secrets
- ✅ Store all new credentials in 1Password Automation vault
- ✅ Validate the fresh setup

### Phase 3: Cluster Bootstrap

```bash
# Apply fresh configuration to nodes
task talos:apply-config

# Bootstrap the cluster with fresh secrets
task talos:bootstrap

# Deploy 1Password Connect with new credentials
task bootstrap:1password-secrets

# Complete the bootstrap process
task bootstrap:phased
```

### Phase 4: Validation

```bash
# Validate 1Password Connect integration
task bootstrap:validate-1password-secrets

# Verify cluster status
task cluster:status

# Test external secrets integration
kubectl get clustersecretstores
kubectl get externalsecrets --all-namespaces
```

## Security Considerations

### What Gets Rotated

- **1Password Connect Server**: Completely new server with fresh credentials
- **Connect Credentials File**: New `1password-credentials.json` (version 2)
- **Connect Token**: Fresh JWT token with new expiration
- **Cloudflare Tunnel**: New tunnel with fresh credentials and tunnel ID
- **Talos Cluster Secrets**: New cluster ID, bootstrap token, encryption keys
- **PKI Certificates**: Fresh etcd, Kubernetes, and OS certificates
- **Service Account Keys**: New Kubernetes service account signing keys

### What Stays the Same

- **Cluster Configuration**: Node IPs, network settings, patches
- **Application Manifests**: GitOps configurations remain unchanged
- **1Password Vault Structure**: Same vaults, just new credentials

### Security Benefits

- **Complete Invalidation**: Old credentials cannot be used even if still cached
- **Fresh PKI**: No certificate reuse or potential compromise
- **Clean State**: No residual secrets from compromised environment
- **Audit Trail**: Clear before/after credential rotation in 1Password

## 1Password Vault Organization

After rotation, credentials are stored in the **Automation** vault:

```
Automation Vault:
├── 1Password Connect Credentials - home-ops (Document)
├── 1Password Connect Token - home-ops (API Credential)
├── Home-ops cloudflare-tunnel.json (Document)
└── Talos Secrets - home-ops (Secure Note)
```

### Entry Details

**1Password Connect Credentials - home-ops**
- Type: Document
- Contains: Fresh `1password-credentials.json` file
- Version: 2 (required for Connect API)

**1Password Connect Token - home-ops**
- Type: API Credential
- Field: `token` (password field)
- Contains: Fresh JWT Connect token

**Home-ops cloudflare-tunnel.json**
- Type: Document
- Field: `json` (password field)
- Contains: Fresh Cloudflare tunnel credentials JSON

**Talos Secrets - home-ops**
- Type: Secure Note
- Field: `talsecret` (password field)
- Contains: Complete Talos secret YAML

## Troubleshooting

### Common Issues

**1. "Connect server creation failed"**
```bash
# Check 1Password CLI authentication
op account list
op signin

# Verify account access
echo $OP_ACCOUNT
```

**2. "Nodes not in maintenance mode"**
```bash
# Check node status
talosctl version --insecure --nodes 172.29.51.11

# If needed, reset nodes safely
task cluster:safe-reset CONFIRM=SAFE-RESET
```

**3. "Talos config generation failed"**
```bash
# Clean up and retry
rm -rf talos/generated/*
rm -f talos/talsecret.yaml
task talos:generate-config
```

**4. "1Password Connect deployment fails"**
```bash
# Check secrets exist
kubectl get secrets -n onepassword-connect

# Validate secret content
kubectl get secret onepassword-connect-credentials -n onepassword-connect -o yaml

# Restart deployment
kubectl rollout restart deployment onepassword-connect -n onepassword-connect
```

### Recovery Procedures

**If credential rotation fails midway:**

1. **Reset to clean state**:
   ```bash
   task cluster:safe-reset CONFIRM=SAFE-RESET
   ```

2. **Clean up partial entries**:
   ```bash
   # Manually clean up any partial 1Password entries
   op item list --vault=Automation | grep -E "(Connect|Talos)"
   ```

3. **Start over**:
   ```bash
   task onepassword:prepare-credential-rotation
   task onepassword:bootstrap-fresh-credentials
   ```

**If cluster becomes inaccessible:**

1. **Emergency recovery**:
   ```bash
   task cluster:emergency-recovery
   ```

2. **Safe reboot alternative**:
   ```bash
   task cluster:safe-reboot
   ```

## Validation Checklist

After completing credential rotation:

- [ ] All old 1Password Connect servers revoked
- [ ] Fresh credentials stored in 1Password Automation vault
- [ ] Nodes successfully configured with fresh Talos config
- [ ] Cluster bootstrapped and accessible
- [ ] 1Password Connect deployed and healthy
- [ ] External Secrets operator can access 1Password
- [ ] All infrastructure applications deployed successfully
- [ ] No old credential files remain locally

## Security Incident Response Complete

Once this process is complete:

✅ **Compromised credentials invalidated**
✅ **Fresh secrets generated and secured**
✅ **Cluster rebuilt with clean credentials**
✅ **GitOps pipeline restored**
✅ **Security posture improved**

The security incident response is considered complete when all validation checks pass and the cluster is fully operational with fresh credentials.

## Maintenance

### Regular Credential Rotation

For routine maintenance (not incident response):

```bash
# Generate new Connect token (keeps same server)
task onepassword:create-connect-server

# Rotate Talos secrets (planned maintenance)
task talos:generate-config
```

### Monitoring

- **Connect Token Expiration**: Tokens expire after 8760h (1 year)
- **Certificate Expiration**: Talos manages certificate rotation automatically
- **1Password Audit**: Review access logs in 1Password Business console

---

**Document Version**: 1.0  
**Last Updated**: 2025-07-16  
**Security Incident**: Resolved via complete credential rotation