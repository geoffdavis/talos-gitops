# Cluster Rebuild Fixes - July 2025

This document details the issues encountered during the cluster rebuild and the fixes applied.

## Issues Encountered

### 1. DNS Resolution Failure with Custom Cluster Domain

**Problem**: Flux components failed to communicate because they were trying to resolve services using `.cluster.local` domain, but the cluster was configured with a custom domain `k8s.home.geoffdavis.com`.

**Fix**: Reverted to using the default `cluster.local` domain by commenting out the custom domain in `talconfig.yaml`:

```yaml
# domain: k8s.home.geoffdavis.com  # Using default cluster.local
```

### 2. API Server Failed to Start

**Problem**: The kube-apiserver failed to start with two errors:
- OIDC authenticator initialization failed trying to connect to `https://auth.homelab.local`
- PodSecurity admission plugin error due to duplicate `kube-system` namespace in exemptions

**Fix**: 
1. Updated OIDC issuer URL in `talconfig.yaml` to the correct domain:
   ```yaml
   oidc-issuer-url: https://auth.k8s.home.geoffdavis.com
   ```

2. Fixed duplicate namespace issue (this is a talhelper generation bug that requires manual fixing after generation)

### 3. Network Interface Name Change

**Problem**: VIP configuration was using incorrect network interface name `eth0`.

**Fix**: Updated to the correct interface name `enp3s0f0` in `talconfig.yaml`:

```yaml
- interface: enp3s0f0
  vip:
    ip: 172.29.51.10
```

### 4. Mac Mini USB Support

**Problem**: Mac minis require hard reboots for proper USB device detection.

**Fix**: Added sysctl to disable kexec in `talconfig.yaml`:

```yaml
sysctls:
  kernel.kexec_load_disabled: "1"  # Disable kexec for Mac mini USB support
```

## Task Improvements

### 1. Fixed Reboot Task

Updated `talos:reboot` task in `Taskfile.yml` to properly accept NODES parameter:

```yaml
talos:reboot:
  desc: Reboot specified nodes or all nodes (for USB detection)
  env:
    TALOSCONFIG: clusterconfig/talosconfig
  vars:
    NODES: '{{.NODES | default "all"}}'
```

### 2. Added Apply Config Without Regeneration

Created `talos:apply-config-only` task to apply configuration without regenerating (useful when manually fixing generated files):

```yaml
talos:apply-config-only:
  desc: Apply Talos configuration to nodes (without regenerating)
  env:
    TALOSCONFIG: clusterconfig/talosconfig
  cmds:
    - echo "Applying Talos configuration to all control plane nodes..."
    - |
      talosctl apply-config --nodes {{.NODE_1_IP}} --file clusterconfig/home-ops-mini01.yaml || \
      talosctl apply-config --insecure --nodes {{.NODE_1_IP}} --file clusterconfig/home-ops-mini01.yaml
    # ... (similar for other nodes)
```

### 3. Fixed Helm Repo Exists Error

Updated `apps:deploy-cilium` to handle existing helm repo:

```yaml
- helm repo add cilium https://helm.cilium.io/ || true
```

## Rebuild Process Summary

1. **Reset all nodes**: Nodes were wiped and rebooted from USB installers
2. **Fixed configuration**: Updated `talconfig.yaml` with all fixes mentioned above
3. **Generated new configuration**: `task talos:generate-config`
4. **Applied configuration**: `task talos:apply-config`
5. **Bootstrapped cluster**: `task talos:bootstrap`
6. **Fixed API server issues**: 
   - Manually fixed duplicate namespace in generated configs
   - Applied configuration without regenerating
   - Restarted kubelet to force static pod recreation
7. **Deployed Cilium CNI**: `task apps:deploy-cilium`
8. **Verified cluster health**: All nodes Ready, API server running

## Key Learnings

1. **Default cluster domain**: Stick with `cluster.local` unless you have a specific need for a custom domain
2. **Configuration validation**: Always check generated configurations for issues before applying
3. **Mac mini specifics**: Disable kexec for proper USB support
4. **Network interfaces**: Verify correct interface names before configuration
5. **OIDC configuration**: Ensure issuer URLs are accessible and correctly configured

## Updated Cilium Configuration

The Cilium configuration in `Taskfile.yml` now uses cluster-pool IPAM mode:

```yaml
--set ipam.mode=cluster-pool
--set ipam.operator.clusterPoolIPv4PodCIDRList="10.244.0.0/16"
--set ipam.operator.clusterPoolIPv4MaskSize=24
```

This provides better IP address management for the cluster.