# Bootstrap Troubleshooting Guide

## Overview

This guide provides comprehensive troubleshooting for the phased bootstrap process. Each phase has specific failure modes and recovery procedures.

## Quick Diagnosis

### Check Bootstrap Status

```bash
# Show current status and any failures
task bootstrap:status

# View logs for failed phase
task bootstrap:logs PHASE=<failed_phase>

# Resume from failed phase
task bootstrap:resume
```

### Common Recovery Commands

```bash
# Reset and start over
task bootstrap:reset
task bootstrap:phased

# Validate specific phase
task validate:phase-1  # Environment
task validate:phase-2  # Cluster
task validate:phase-3  # Networking
```

## Phase 1: Environment Validation Failures

### Issue: Mise Not Installed

**Symptoms**:

- `mise: command not found`
- Phase 1 fails immediately

**Solution**:

```bash
# Install mise
curl https://mise.run | sh

# Add to shell profile
echo 'eval "$(mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

# Verify installation
mise --version
```

### Issue: Tools Not Available

**Symptoms**:

- `tool not found` errors
- Version mismatch warnings

**Solution**:

```bash
# Install all tools
mise install

# Check specific tool
mise exec -- kubectl version

# Reinstall specific tool
mise uninstall kubectl
mise install kubectl
```

### Issue: 1Password Authentication Failed

**Symptoms**:

- `op account list` fails
- Cannot access 1Password items

**Solution**:

```bash
# Sign in to 1Password
op signin

# Verify authentication
op account list

# Check specific item access
op item get "1password connect" --vault="Automation"
```

### Issue: Environment Variables Missing

**Symptoms**:

- `OP_ACCOUNT environment variable is not set`

**Solution**:

```bash
# Set environment variable
export OP_ACCOUNT=your-account-name

# Or add to .env file
echo "OP_ACCOUNT=your-account-name" >> .env

# Verify
echo $OP_ACCOUNT
```

### Issue: Network Connectivity Problems

**Symptoms**:

- Cannot reach nodes
- Internet connectivity failed

**Solution**:

```bash
# Check node connectivity
ping 172.29.51.11
ping 172.29.51.12
ping 172.29.51.13

# Check internet
ping 8.8.8.8

# Check DNS
nslookup github.com
```

## Phase 2: Talos Cluster Initialization Failures

### Issue: Secret Bootstrap Failed

**Symptoms**:

- Cannot retrieve secrets from 1Password
- Missing required 1Password items

**Solution**:

```bash
# Check 1Password items exist
op item get "1password connect" --vault="Automation"
op item get "Cloudflare API Token" --vault="Automation"

# Run secret bootstrap manually
task bootstrap:secrets

# Verify secrets were created
ls -la talos/talsecret.yaml
```

### Issue: Talos Configuration Generation Failed

**Symptoms**:

- `talhelper` command fails
- Configuration files not created

**Solution**:

```bash
# Check talhelper is available
mise exec -- talhelper --version

# Generate configuration manually
task talos:generate-config

# Verify configuration files
ls -la clusterconfig/
```

### Issue: Node Configuration Application Failed

**Symptoms**:

- Cannot connect to nodes
- Certificate errors

**Solution**:

```bash
# Check node accessibility
talosctl --talosconfig clusterconfig/talosconfig version --nodes 172.29.51.11

# Apply configuration with insecure mode
talosctl apply-config --insecure --nodes 172.29.51.11 --file clusterconfig/home-ops-mini01.yaml

# Check node status
talosctl --talosconfig clusterconfig/talosconfig health --nodes 172.29.51.11
```

### Issue: etcd Bootstrap Failed

**Symptoms**:

- Bootstrap command fails
- etcd pods not starting

**Solution**:

```bash
# Check node readiness
talosctl --talosconfig clusterconfig/talosconfig get members --nodes 172.29.51.11

# Retry bootstrap
talosctl --talosconfig clusterconfig/talosconfig bootstrap --nodes 172.29.51.11

# Check etcd status
kubectl get pods -n kube-system -l component=etcd
```

### Issue: Cluster API Not Accessible

**Symptoms**:

- `kubectl` commands fail
- Cannot retrieve kubeconfig

**Solution**:

```bash
# Retrieve kubeconfig
talosctl --talosconfig clusterconfig/talosconfig kubeconfig --nodes 172.29.51.11 --force

# Test cluster access
kubectl get nodes

# Check cluster endpoint
kubectl cluster-info
```

## Phase 3: CNI Deployment Failures

### Issue: Cilium Deployment Failed

**Symptoms**:

- Cilium pods not starting
- Helm deployment errors

**Solution**:

```bash
# Check Cilium deployment
kubectl get pods -n kube-system -l k8s-app=cilium

# Redeploy Cilium
task apps:deploy-cilium

# Check Cilium logs
kubectl logs -n kube-system -l k8s-app=cilium
```

### Issue: Nodes Not Becoming Ready

**Symptoms**:

- Nodes stuck in "NotReady" state
- Pod networking not working

**Solution**:

```bash
# Check node conditions
kubectl describe nodes

# Check CNI configuration
kubectl get ds -n kube-system cilium

# Restart Cilium
kubectl rollout restart daemonset/cilium -n kube-system
```

### Issue: Pod Networking Tests Failed

**Symptoms**:

- Test pods cannot start
- DNS resolution fails

**Solution**:

```bash
# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test pod networking manually
kubectl run test-pod --image=busybox --rm -it -- /bin/sh

# Check service endpoints
kubectl get endpoints kubernetes
```

## Phase 4: Core Services Failures

### Issue: External Secrets Operator Failed

**Symptoms**:

- External Secrets pods not running
- CRDs not installed

**Solution**:

```bash
# Check External Secrets installation
kubectl get pods -n external-secrets-system

# Reinstall External Secrets
task apps:deploy-external-secrets

# Check CRDs
kubectl get crd | grep external-secrets
```

### Issue: 1Password Connect Failed

**Symptoms**:

- 1Password Connect pods not starting
- Secret retrieval fails

**Solution**:

```bash
# Check 1Password Connect pods
kubectl get pods -n onepassword-connect

# Check secrets exist
kubectl get secrets -n onepassword-connect

# Recreate 1Password secrets
task bootstrap:1password-secrets
```

### Issue: Longhorn Storage Failed

**Symptoms**:

- Longhorn pods not starting
- Storage not available

**Solution**:

```bash
# Check Longhorn installation
kubectl get pods -n longhorn-system

# Check storage nodes
kubectl get nodes.longhorn.io -n longhorn-system

# Redeploy Longhorn
task apps:deploy-longhorn
```

## Phase 5: GitOps Deployment Failures

### Issue: Flux Bootstrap Failed

**Symptoms**:

- Cannot connect to GitHub
- Repository access denied

**Solution**:

```bash
# Check GitHub token
op read "op://Private/GitHub Personal Access Token/token"

# Test GitHub access
curl -H "Authorization: token $(op read 'op://Private/GitHub Personal Access Token/token')" https://api.github.com/user

# Retry Flux bootstrap
task flux:bootstrap
```

### Issue: GitOps Sync Failed

**Symptoms**:

- Flux not reconciling
- Infrastructure not deploying

**Solution**:

```bash
# Check Flux status
flux get kustomizations

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system

# Check Flux logs
kubectl logs -n flux-system -l app=source-controller
```

## Phase 6: Application Deployment Failures

### Issue: Applications Not Deploying

**Symptoms**:

- Application pods not starting
- Kustomization failures

**Solution**:

```bash
# Check application status
flux get kustomizations | grep apps

# Check specific application
kubectl get all -n <app-namespace>

# Force application reconciliation
flux reconcile kustomization apps-<app-name>
```

## General Recovery Procedures

### Complete Reset and Restart

```bash
# Reset bootstrap state
task bootstrap:reset

# Start fresh
task bootstrap:phased
```

### Partial Recovery

```bash
# Resume from specific phase
task bootstrap:resume-from PHASE=3

# Validate before resuming
task validate:phase-2
task bootstrap:resume-from PHASE=3
```

### Emergency Cluster Access

```bash
# Recover kubeconfig
task talos:recover-kubeconfig

# Check cluster health
task cluster:status

# Emergency recovery
task cluster:emergency-recovery
```

## Diagnostic Commands

### Environment Diagnostics

```bash
# Comprehensive mise validation
./scripts/validate-mise-environment.sh

# Check tool versions
mise ls --installed

# Test tool execution
mise exec -- kubectl version
mise exec -- talosctl version
```

### Cluster Diagnostics

```bash
# Node status
kubectl get nodes -o wide

# Pod status
kubectl get pods --all-namespaces | grep -v Running

# Events
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Talos health
talosctl health --nodes 172.29.51.11,172.29.51.12,172.29.51.13
```

### Network Diagnostics

```bash
# Cilium status
kubectl get pods -n kube-system -l k8s-app=cilium

# Service connectivity
kubectl get svc --all-namespaces

# Load balancer status
kubectl get svc --all-namespaces | grep LoadBalancer
```

## Log Analysis

### Bootstrap Logs

```bash
# View orchestrator log
cat logs/bootstrap/orchestrator.log

# View specific phase log
cat logs/bootstrap/phase-2.log

# View validation log
cat logs/bootstrap/validate-phase-3.log
```

### Kubernetes Logs

```bash
# Control plane logs
kubectl logs -n kube-system -l tier=control-plane

# CNI logs
kubectl logs -n kube-system -l k8s-app=cilium

# GitOps logs
kubectl logs -n flux-system -l app=source-controller
```

## Prevention Strategies

### Pre-Bootstrap Checks

```bash
# Validate environment before starting
./scripts/validate-mise-environment.sh

# Check network connectivity
ping 172.29.51.11 && ping 172.29.51.12 && ping 172.29.51.13

# Verify 1Password access
op item get "1password connect" --vault="Automation"
```

### Regular Validation

```bash
# Run all phase validations
task validate:all-phases

# Check cluster health
task cluster:status

# Verify GitOps sync
flux get kustomizations
```

## Getting Help

### Documentation References

- [Phased Bootstrap Guide](./PHASED_BOOTSTRAP_GUIDE.md)
- [Bootstrap vs GitOps Phases](./BOOTSTRAP_VS_GITOPS_PHASES.md)
- [Cluster Reset Safety](./CLUSTER_RESET_SAFETY.md)
- [Operational Workflows](./OPERATIONAL_WORKFLOWS.md)

### Log Files to Check

- `logs/bootstrap/orchestrator.log` - Master orchestrator log
- `logs/bootstrap/phase-N.log` - Phase execution logs
- `logs/bootstrap/validate-phase-N.log` - Validation logs
- `logs/bootstrap/phase-N-*-report.txt` - Detailed phase reports

### Common Support Commands

```bash
# Generate comprehensive status report
task bootstrap:status > bootstrap-status.txt

# Collect all logs
tar -czf bootstrap-logs.tar.gz logs/bootstrap/

# Environment report
./scripts/validate-mise-environment.sh > environment-report.txt
```

Remember: The phased bootstrap approach is designed to eliminate the need for cluster resets. Always try to resume from the failed phase rather than starting over completely.
