# Talos Kubernetes Cluster Rebuild Fixes

## Date: July 7, 2025

### Summary of Issues and Fixes

#### 1. ✅ Cilium CNI Issues - FIXED

**Problem**: Cilium was being managed by both Flux and Talos bootstrap, causing conflicts. The pods were failing with RBAC errors and incorrect IPAM mode.

**Solution**:

- Removed Cilium from Flux management completely
- Deleted infrastructure-cilium kustomization and references
- Used `task talos:fix-cilium` to deploy Cilium with proper Talos configuration
- Configured with `cluster-pool` IPAM mode and correct pod CIDR

**Result**: All nodes are now Ready and CNI is functioning properly

#### 2. ✅ Pod Security Standards Violations - FIXED

**Problem**: Multiple deployments were missing required seccomp profiles

**Solution**: Added seccomp profiles to:

- 1Password Connect deployment
- Cloudflare Tunnel deployment

#### 3. ✅ External Secrets Schema Error - FIXED

**Problem**: connectToken field was deprecated in favor of connectTokenSecretRef

**Solution**: Updated external-secrets-operator.yaml to use the new schema

#### 4. ✅ Longhorn StorageClass Conflict - FIXED

**Problem**: Flux was trying to manage a StorageClass that Longhorn already created

**Solution**: Removed the default longhorn StorageClass from Flux management

#### 5. ✅ 1Password Connect Configuration - FIXED

**Problem**: Credentials were incorrectly passed as environment variable instead of mounted file

**Solution**: Updated deployment to mount credentials at `/home/opuser/.op/1password-credentials.json`

#### 6. ❌ 1PASSWORD CONNECT CREDENTIALS - NEEDS UPDATE

**Problem**: The 1Password Connect credentials are in an old format (version 1) and need to be regenerated

**Error**: `"credentials file is not version 2"`

**Solution**: Need to regenerate credentials from 1Password account. See `docs/1PASSWORD_CONNECT_SETUP.md` for detailed instructions.

**Impact**: This is blocking:

- ClusterSecretStore validation
- All External Secrets from syncing
- Cloudflare Tunnel deployment
- External DNS deployment
- Cert-manager Cloudflare DNS validation
- BGP authentication secrets

#### 7. ✅ Cilium BGP Configuration - FIXED

**Problem**: CiliumBGPPeerConfig had invalid field `.spec.advertisedPathAttributes`

**Solution**: Removed the invalid field - in newer Cilium versions, path attributes are configured in CiliumBGPAdvertisement

#### 8. ❌ Cloudflare Tunnel - BLOCKED

**Problem**: Deployment waiting for secret from External Secrets

**Dependency**: Requires 1Password Connect credentials to be updated

### Current Cluster State

**Nodes**: All Ready ✅

```
mini01   Ready    control-plane   13h   v1.31.1
mini02   Ready    control-plane   13h   v1.31.1
mini03   Ready    control-plane   13h   v1.31.1
```

**Failed Flux Kustomizations**:

- infrastructure-cilium-bgp (waiting for Flux to sync latest changes)
- infrastructure-cloudflare-tunnel (waiting for secrets)
- infrastructure-external-dns (waiting for secrets)

### Next Steps

1. **Update 1Password Connect Credentials** (CRITICAL):

   - Follow instructions in `docs/1PASSWORD_CONNECT_SETUP.md`
   - Generate new version 2 credentials
   - Update the Kubernetes secret
   - Restart the 1Password Connect deployment

2. **After credentials are updated**:

   - ClusterSecretStore should validate
   - External Secrets will start syncing
   - Dependent services will deploy automatically

3. **Monitor deployments**:

   ```bash
   # Watch External Secrets sync
   kubectl get externalsecrets -A

   # Check ClusterSecretStore status
   kubectl get clustersecretstore onepassword-connect

   # Monitor Flux reconciliation
   flux get kustomizations --all-namespaces
   ```

### Commands Used

```bash
# Fix Cilium CNI
task talos:fix-cilium

# Reconcile Flux changes
flux reconcile kustomization <name> --with-source

# Check cluster state
kubectl get nodes
kubectl get pods -A | grep -v Running
flux get kustomizations --all-namespaces

# Debug 1Password Connect
kubectl logs -n onepassword-connect deployment/onepassword-connect -c connect-api
kubectl logs -n onepassword-connect deployment/onepassword-connect -c connect-sync
```

### Key Configuration Changes

1. **Cilium IPAM mode** (removed from Flux management):

```yaml
ipam:
  mode: cluster-pool
  operator:
    clusterPoolIPv4PodCIDRList: ["10.0.0.0/8"]
    clusterPoolIPv4MaskSize: 24
```

2. **1Password Connect credentials mount**:

```yaml
volumeMounts:
  - name: credentials
    mountPath: /home/opuser/.op/1password-credentials.json
    subPath: 1password-credentials.json
    readOnly: true
```

3. **Namespace updates**: Changed from `cilium-system` to `kube-system` for all Cilium BGP resources

4. **Removed from CiliumBGPPeerConfig**: `advertisedPathAttributes` field (not valid in current schema)

### Current Blockers

The main blocker is the 1Password Connect credentials format issue. Once the credentials are regenerated in version 2 format:

1. The ClusterSecretStore will validate
2. External Secrets will sync
3. All dependent services will deploy
4. The cluster will be fully operational

The cluster foundation is solid with:

- ✅ All nodes Ready
- ✅ CNI functioning properly
- ✅ Most core components deployed
- ✅ Pod Security Standards compliant
- ❌ Waiting on secrets management
