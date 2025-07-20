# Flux Timeout Troubleshooting Guide

This document provides comprehensive troubleshooting procedures for Flux reconciliation timeout scenarios and operational best practices.

## Overview

This guide covers timeout configurations implemented across the GitOps infrastructure to prevent reconciliation hangs and ensure robust operations.

## Timeout Configuration Summary

### HelmRelease Timeouts

| Component | Timeout | Install | Upgrade | Rollback | Rationale |
|-----------|---------|---------|---------|----------|-----------|
| Longhorn | 20m | 20m | 20m | 15m | Complex storage infrastructure |
| Cilium | 20m | 20m | 20m | 10m | Critical networking infrastructure |
| cert-manager | 15m | 15m | 15m | 10m | Standard application with CRDs |
| ingress-nginx | 15m | 15m | 15m | 10m | Standard application with dependencies |
| external-dns | 10m | 10m | 10m | 5m | Simple application |

### Kustomization Timeouts

| Layer | Timeout | Retry Interval | Rationale |
|-------|---------|----------------|-----------|
| Sources | 5m | 2m | Simple resource definitions |
| Core Infrastructure | 10m | 2m | External secrets, 1Password |
| Storage Infrastructure | 20m | 3m | Longhorn complexity |
| Networking Infrastructure | 15m | 2m | Ingress, DNS, tunnels |
| Applications | 5-10m | 1-2m | Simple applications |

### Source Timeouts

| Source Type | Timeout | Rationale |
|-------------|---------|-----------|
| GitRepository | 60s | Git clone/fetch operations |
| HelmRepository | 5m | Helm index download |

## Common Timeout Scenarios

### 1. HelmRelease Installation Timeout

**Symptoms:**
- HelmRelease stuck in "Installing" state
- Timeout exceeded error in Flux logs
- Pods not starting or in pending state

**Troubleshooting Steps:**

```bash
# Check HelmRelease status
kubectl get helmrelease -A

# Describe specific HelmRelease
kubectl describe helmrelease <name> -n <namespace>

# Check Helm release status directly
helm list -A
helm status <release-name> -n <namespace>

# Check pod status and events
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# Check resource constraints
kubectl top nodes
kubectl describe nodes
```

**Common Causes:**
- Insufficient cluster resources (CPU/Memory)
- Image pull failures
- Storage provisioning issues
- Network connectivity problems
- Dependency services not ready

**Resolution:**
1. Verify cluster resources are sufficient
2. Check image availability and pull secrets
3. Ensure storage classes are configured
4. Verify network policies and connectivity
5. Check dependency service health

### 2. Kustomization Reconciliation Timeout

**Symptoms:**
- Kustomization stuck in "Reconciling" state
- Health checks failing
- Dependent resources not deploying

**Troubleshooting Steps:**

```bash
# Check Kustomization status
kubectl get kustomization -A

# Describe specific Kustomization
kubectl describe kustomization <name> -n flux-system

# Check Flux controller logs
kubectl logs -n flux-system deployment/kustomize-controller

# Check health check targets
kubectl get <resource-type> <resource-name> -n <namespace>
kubectl describe <resource-type> <resource-name> -n <namespace>
```

**Common Causes:**
- Health check targets not ready
- Resource creation failures
- RBAC permission issues
- Network policies blocking access

**Resolution:**
1. Verify health check targets are correct
2. Check resource creation logs and events
3. Validate RBAC permissions
4. Review network policies

### 3. GitRepository Sync Timeout

**Symptoms:**
- GitRepository shows "Timeout" condition
- Source controller unable to fetch repository
- Stale artifact references

**Troubleshooting Steps:**

```bash
# Check GitRepository status
kubectl get gitrepository -A

# Describe GitRepository
kubectl describe gitrepository flux-system -n flux-system

# Check source controller logs
kubectl logs -n flux-system deployment/source-controller

# Test Git connectivity
kubectl run git-test --rm -it --image=alpine/git -- git ls-remote <repository-url>
```

**Common Causes:**
- Network connectivity issues
- Git repository authentication failures
- Large repository size
- Git server performance issues

**Resolution:**
1. Verify network connectivity to Git server
2. Check authentication credentials
3. Consider repository optimization
4. Increase timeout if necessary

### 4. HelmRepository Refresh Timeout

**Symptoms:**
- HelmRepository shows "Timeout" condition
- Unable to download Helm index
- Chart versions not updating

**Troubleshooting Steps:**

```bash
# Check HelmRepository status
kubectl get helmrepository -A

# Describe HelmRepository
kubectl describe helmrepository <name> -n flux-system

# Test Helm repository connectivity
kubectl run helm-test --rm -it --image=alpine/helm -- helm repo add test <repository-url>
```

**Common Causes:**
- Network connectivity to Helm repository
- Repository server performance issues
- Large index files
- Authentication issues

**Resolution:**
1. Verify network connectivity
2. Check repository server status
3. Consider repository mirroring
4. Increase timeout if necessary

## Monitoring and Alerting

### Prometheus Alerts

The following alerts are configured to detect timeout scenarios:

- **FluxReconciliationDurationHigh**: Warns when reconciliation takes longer than 5 minutes
- **FluxHelmReleaseReconciliationFailure**: Critical alert for HelmRelease failures
- **FluxKustomizationReconciliationFailure**: Critical alert for Kustomization failures
- **FluxGitRepositoryReconciliationFailure**: Warning for GitRepository sync failures
- **FluxHelmRepositoryReconciliationFailure**: Warning for HelmRepository refresh failures

### Monitoring Queries

```promql
# Reconciliation duration by resource type
gotk_reconcile_duration_seconds{quantile="0.99"}

# Failed reconciliations
increase(gotk_reconcile_condition{type="Ready",status="False"}[10m])

# Suspended resources
gotk_suspend_status == 1

# Controller availability
up{job=~"flux-system.*"}
```

## Recovery Procedures

### 1. Force Reconciliation

```bash
# Force reconcile a specific resource
flux reconcile source git flux-system
flux reconcile kustomization <name>
flux reconcile helmrelease <name> -n <namespace>
```

### 2. Suspend and Resume

```bash
# Suspend problematic resource
flux suspend kustomization <name>
flux suspend helmrelease <name> -n <namespace>

# Resume after fixing issues
flux resume kustomization <name>
flux resume helmrelease <name> -n <namespace>
```

### 3. Reset Stuck Resources

```bash
# Delete and recreate Flux resources
kubectl delete kustomization <name> -n flux-system
kubectl delete helmrelease <name> -n <namespace>

# Flux will recreate from Git
```

### 4. Emergency Procedures

For critical infrastructure components (Longhorn, Cilium):

```bash
# Check cluster node status
kubectl get nodes
talosctl health --nodes <node-ips>

# Check system resources
kubectl top nodes
kubectl describe nodes

# Emergency cluster recovery
talosctl reboot --nodes <node-ips>
```

## Prevention Best Practices

### 1. Resource Planning

- Monitor cluster resource utilization
- Plan for peak resource requirements
- Implement resource quotas and limits
- Use node affinity for critical components

### 2. Dependency Management

- Properly configure `dependsOn` relationships
- Use health checks for critical dependencies
- Implement proper startup ordering
- Avoid circular dependencies

### 3. Network Reliability

- Implement network policies carefully
- Use reliable DNS resolution
- Configure appropriate service meshes
- Monitor network connectivity

### 4. Storage Considerations

- Ensure storage classes are available
- Monitor storage capacity
- Use appropriate storage types for workloads
- Implement backup strategies

## Timeout Adjustment Guidelines

### When to Increase Timeouts

- Consistently hitting timeout limits
- Large or complex applications
- Resource-constrained environments
- Network latency issues

### When to Decrease Timeouts

- Fast-failing scenarios preferred
- Simple applications
- Well-resourced environments
- Quick feedback loops needed

### Configuration Changes

To adjust timeouts, modify the appropriate configuration files:

- HelmRelease timeouts: `infrastructure/*/helmrelease.yaml`
- Kustomization timeouts: `clusters/home-ops/infrastructure/*.yaml`
- Source timeouts: `infrastructure/sources/helm-repositories.yaml`

## Escalation Procedures

### Level 1: Automatic Recovery
- Flux retry mechanisms
- Health check failures
- Automatic rollbacks

### Level 2: Manual Intervention
- Force reconciliation
- Resource suspension/resumption
- Configuration adjustments

### Level 3: Emergency Response
- Cluster node intervention
- Manual application deployment
- Infrastructure recovery procedures

## Related Documentation

- [Operational Workflows](OPERATIONAL_WORKFLOWS.md)
- [Component Migration Guide](COMPONENT_MIGRATION_GUIDE.md)
- [Bootstrap vs GitOps Architecture](BOOTSTRAP_VS_GITOPS_ARCHITECTURE.md)
- [Core Idempotency Verification](CORE_IDEMPOTENCY_VERIFICATION.md)

## Maintenance Schedule

- **Daily**: Monitor alert status and reconciliation health
- **Weekly**: Review timeout metrics and adjust if needed
- **Monthly**: Analyze timeout trends and optimize configurations
- **Quarterly**: Review and update timeout policies