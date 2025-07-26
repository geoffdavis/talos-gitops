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

## Recovery Order and Dependencies

The recovery process has critical dependencies that must be resolved in order:

1. **Cilium CNI** - Must be running before any new pods can start
2. **1Password Connect** - Required before External Secrets can sync
3. **External Secrets** - Must be validating before dependent services can get secrets
4. **All other services** - Can deploy once secrets are available

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
    --set ipam.mode=cluster-pool \
    --set ipam.operator.clusterPoolIPv4PodCIDRList="10.244.0.0/16" \
    --set ipam.operator.clusterPoolIPv4MaskSize=24 \
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
- **1Password Connect Server** - Created via CLI, provides access to vaults
- **JWT Token** - Must be created for the same Connect server that has the credentials.json

### 1Password Vaults Configuration

The cluster accesses two vaults:

- **Automation** (vault ID: 1)
- **Services** (vault ID: 2) - Note: This is "Services", not "Shared"

Ensure your ClusterSecretStore configuration matches:

```yaml
vaults:
  Automation: 1
  Services: 2
```

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

### Cilium Pods Crashing or in Unknown Status

If Cilium pods are in CrashLoopBackOff or Unknown status:

1. Check if kube-proxy is disabled in the cluster
2. Ensure Cilium is configured with the correct k8sServiceHost and k8sServicePort
3. Verify the capabilities are set correctly (no SYS_MODULE for Talos)
4. If all Cilium pods show Unknown status, redeploy Cilium completely:
   ```bash
   task apps:deploy-cilium
   ```

### 1Password Connect Issues

If External Secrets shows ClusterSecretStore as ValidationFailed:

1. **Check 1Password Connect pods**:

   ```bash
   kubectl get pods -n onepassword-connect
   kubectl logs -n onepassword-connect <pod-name> connect-api
   ```

2. **Common errors**:

   - "credentials file is not version 2" - Old or invalid credentials
   - "failed to FindCredentialsUniqueKey" - Mismatch between JWT token and credentials
   - "illegal base64 data" - Invalid dummy credentials file

3. **Recreate 1Password Connect server and token** (must be done together):

   ```bash
   # Delete old server if exists
   op connect server delete "Kubernetes home-ops"

   # Create new server with correct vaults (Automation and Services)
   op connect server create "Kubernetes home-ops" --vaults="Automation,Services"

   # Create matching JWT token
   op connect token create "kubernetes-external-secrets" \
     --server "Kubernetes home-ops" \
     --vault "Automation" \
     --vault "Services"
   ```

4. **Update Kubernetes secrets**:

   ```bash
   # Update credentials
   kubectl create secret generic onepassword-connect-credentials \
     --from-file=1password-credentials.json=1password-credentials.json \
     --namespace=onepassword-connect \
     --dry-run=client -o yaml | kubectl apply -f -

   # Update JWT token (use the token from step 3)
   kubectl create secret generic onepassword-connect-token \
     --from-literal=token="<JWT-TOKEN>" \
     --namespace=onepassword-connect \
     --dry-run=client -o yaml | kubectl apply -f -

   # Restart deployment
   kubectl rollout restart deployment -n onepassword-connect onepassword-connect
   ```

5. **Verify ClusterSecretStore**:
   ```bash
   kubectl get clustersecretstore
   # Should show STATUS: Valid and READY: True
   ```

**Important**: The 1Password Connect Server integration is no longer available in the 1Password web dashboard. You must use the 1Password CLI (`op`) to create Connect servers and tokens.

### API Server Failed to Start

If the API server is in CrashLoopBackOff or continuously exiting:

1. **Check API server logs**:

   ```bash
   talosctl list /var/log/pods --nodes <node-ip> | grep kube-apiserver
   talosctl read /var/log/pods/<apiserver-pod-dir>/kube-apiserver/<latest>.log --nodes <node-ip>
   ```

2. **Common issues**:

   - **OIDC configuration errors**: Ensure the OIDC issuer URL is accessible
   - **PodSecurity admission errors**: Check for duplicate namespaces in exemptions (talhelper bug)
   - **Certificate errors**: Verify all certificates are valid

3. **Fix and restart**:

   - Fix configuration issues in `talconfig.yaml`
   - If fixing generated files manually, use `task talos:apply-config-only`
   - Restart kubelet to force static pod recreation:

     ```bash
     talosctl service kubelet restart --nodes <node-ip>
     ```

### Nodes Not Ready

If nodes remain NotReady after Cilium fix:

1. Check Cilium pod logs: `kubectl logs -n kube-system -l k8s-app=cilium`
2. Verify CoreDNS pods are running
3. Check node logs: `talosctl logs -n <node-ip>`

## Known Issues

### talhelper Configuration Generation

- **Duplicate namespace exemptions**: talhelper may generate duplicate entries in PodSecurity exemptions. After generating config, check for duplicates:

  ```bash
  grep -A2 "kube-system" clusterconfig/home-ops-mini*.yaml
  ```

  If duplicates exist, manually fix them before applying.

### Mac Mini Specific

- **USB devices not detected**: Ensure `kernel.kexec_load_disabled: "1"` is set in sysctls
- **Network interface names**: Mac minis use `enp3s0f0` not `eth0`

### Bootstrap Script Issues

The `bootstrap-k8s-secrets.sh` script may have issues:

1. **BGP secret namespace**: The script originally used `cilium-system` namespace, but BGP configuration is in `kube-system`
2. **1Password item names**: Ensure the script uses the correct item names from your 1Password vault
3. **JWT token retrieval**: The script should get the JWT token from the correct 1Password entry

### Flux Dependency Issues

When recovering, you may see cascading failures due to dependencies:

1. External Secrets must be ready before services requiring secrets
2. Some Flux kustomizations may remain in "dependency not ready" state until 1Password Connect is working
3. Once ClusterSecretStore shows "Valid", dependent services should automatically reconcile

### Recovery Verification

After recovery, verify all systems are operational:

```bash
# Check all nodes are Ready
kubectl get nodes

# Check Cilium CNI is running
kubectl get pods -n kube-system -l k8s-app=cilium

# Check 1Password Connect is running
kubectl get pods -n onepassword-connect

# Check ClusterSecretStore is Valid
kubectl get clustersecretstore

# Check Flux kustomizations
kubectl get kustomization -n flux-system

# Check for any failing pods
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
```
