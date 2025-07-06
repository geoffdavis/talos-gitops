# Cluster Recovery Guide

This guide documents the process for recovering the Talos Kubernetes cluster after a power outage or when experiencing certificate/authentication issues.

## Prerequisites

1. Ensure you have the `.env` file with `OP_ACCOUNT=YourAccountName` set to your 1Password account
2. Ensure you're signed into the correct 1Password account
3. Ensure the cluster nodes are powered on and reachable

## Quick Recovery

Run the comprehensive recovery task:

```bash
task cluster:recover
```

This will:
1. Restore secrets from 1Password
2. Regenerate Talos configuration
3. Recover kubeconfig
4. Fix Cilium CNI configuration
5. Verify cluster status

## Manual Recovery Steps

If the automated recovery doesn't work, follow these manual steps:

### 1. Source Environment Variables

```bash
source .env
```

### 2. Restore Secrets from 1Password

The cluster uses a legacy 1Password entry "talos - home-ops" (not "Talos Secrets - home-ops"):

```bash
task talos:restore-secrets
```

### 3. Generate Talos Configuration

```bash
task talos:generate-config
```

### 4. Recover Kubeconfig

```bash
export TALOSCONFIG=clusterconfig/talosconfig
talosctl kubeconfig --nodes 172.29.51.11 --endpoints 172.29.51.11 --force
```

### 5. Check Node Status

```bash
kubectl get nodes
```

If nodes show "NotReady", it's likely due to Cilium CNI issues.

### 6. Fix Cilium CNI

For Talos clusters without kube-proxy, Cilium requires specific configuration:

```bash
helm upgrade --install cilium cilium/cilium \
    --version 1.15.6 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445
```

Or use the task:

```bash
task talos:fix-cilium
```

### 7. Wait for Nodes to Become Ready

```bash
watch kubectl get nodes
```

All nodes should show "Ready" within a few minutes.

## Key Configuration Details

### 1Password Entries

The cluster uses multiple 1Password entries:
- **"talos - home-ops"** (legacy) - Contains the actual cluster secrets with fields like `cluster_id`, `cluster_secret`, etc.
- **"Talos Secrets - home-ops"** - May contain different/newer secrets

### Cilium Configuration

Critical settings for Talos without kube-proxy:
- `kubeProxyReplacement=true`
- `k8sServiceHost=localhost`
- `k8sServicePort=7445` (KubePrism port)
- Reduced capabilities (no SYS_MODULE)

### Node IPs

- VIP: 172.29.51.10
- mini01: 172.29.51.11
- mini02: 172.29.51.12
- mini03: 172.29.51.13

## Troubleshooting

### Certificate Errors

If you see certificate verification errors:
1. Ensure you're using the correct secrets from 1Password
2. Regenerate the configuration with `task talos:generate-config`
3. Force update kubeconfig with `--force` flag

### Cilium Pods Crashing

If Cilium pods are in CrashLoopBackOff:
1. Check if kube-proxy is disabled in the cluster
2. Ensure Cilium is configured with the correct k8sServiceHost and k8sServicePort
3. Verify the capabilities are set correctly (no SYS_MODULE for Talos)

### Nodes Not Ready

If nodes remain NotReady after Cilium fix:
1. Check Cilium pod logs: `kubectl logs -n kube-system -l k8s-app=cilium`
2. Verify CoreDNS pods are running
3. Check node logs: `talosctl logs -n <node-ip>`