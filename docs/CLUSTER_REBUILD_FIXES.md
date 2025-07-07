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

#### 6. ❌ ClusterSecretStore Validation - IN PROGRESS
**Problem**: onepassword-connect ClusterSecretStore shows ValidationFailed despite pod running

**Current Status**: 
- Pod is running and healthy
- Service endpoints are correct
- Still showing i/o timeout errors when External Secrets tries to validate

#### 7. ❌ Cilium BGP Configuration - NEEDS FIX
**Problem**: CiliumBGPPeerConfig has invalid field `.spec.advertisedPathAttributes`

**Next Steps**: Need to check current Cilium BGP CRD schema

#### 8. ❌ Cloudflare Tunnel - BLOCKED
**Problem**: Deployment waiting for secret from External Secrets

**Dependency**: Requires ClusterSecretStore to be functional

### Current Cluster State

**Nodes**: All Ready ✅
```
mini01   Ready    control-plane   13h   v1.31.1
mini02   Ready    control-plane   13h   v1.31.1
mini03   Ready    control-plane   13h   v1.31.1
```

**Failed Flux Kustomizations**:
- infrastructure-cilium-bgp (schema error)
- infrastructure-cloudflare-tunnel (waiting for secrets)
- infrastructure-external-dns (reconciling)

### Next Steps

1. **Fix ClusterSecretStore validation**:
   - Investigate why 1Password Connect API is timing out
   - Check network connectivity between External Secrets and 1Password Connect
   - Verify 1Password credentials are correctly formatted

2. **Fix Cilium BGP configuration**:
   - Check current CiliumBGPPeerConfig CRD schema
   - Update bgp-policy.yaml to match current schema

3. **Monitor deployments**:
   - Once ClusterSecretStore is working, External Secrets should sync
   - This will unblock Cloudflare Tunnel and other dependent services

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
```

### Key Configuration Changes

1. **Cilium IPAM mode** (infrastructure/cilium/helmrelease.yaml):
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
