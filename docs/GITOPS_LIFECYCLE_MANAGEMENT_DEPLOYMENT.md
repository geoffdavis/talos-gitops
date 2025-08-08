# GitOps Lifecycle Management Deployment Guide

## Overview

This document describes the successful conversion from problematic job patterns to proper Kustomization workflows using the GitOps Lifecycle Management Helm chart.

## Deployment Summary

### ✅ Completed Work

1. **GitOps Lifecycle Management Helm Chart Deployed**
   - Created comprehensive HelmRelease at `infrastructure/gitops-lifecycle-management/helmrelease.yaml`
   - Added to Flux Kustomization in `clusters/home-ops/infrastructure/identity.yaml`
   - Configured with proper 1Password Connect integration
   - Includes authentication hooks, service discovery, database initialization, and cleanup policies

2. **Problematic Jobs Cleaned Up**
   - Updated `infrastructure/authentik-outpost-config/kustomization.yaml` to remove replaced jobs:
     - `enhanced-token-setup-job.yaml` → Replaced by chart's authentication hooks
     - `grafana-oidc-setup-job.yaml` → Replaced by chart's OIDC setup
     - `dashboard-oidc-setup-job.yaml` → Replaced by chart's OIDC setup
     - `cleanup-duplicate-tokens-job.yaml` → Replaced by chart's cleanup policies
   - Only kept `radius-outpost-config-job.yaml` (specialized, not replaced by chart)

3. **Init Container Conversions Maintained**
   - Home Assistant: 3 init containers (database, MQTT, Redis) - database-init-job already removed
   - Dashboard: Kong configuration init container operational
   - Monitoring: Grafana OIDC setup init container operational

4. **Flux Dependency Ordering Updated**
   - GitOps Lifecycle Management chart depends on:
     - `infrastructure-sources`
     - `infrastructure-external-secrets`
     - `infrastructure-onepassword-connect`
     - `infrastructure-authentik`
   - Updated `clusters/home-ops/infrastructure/outpost-config.yaml` to depend on GitOps Lifecycle Management
   - Removed health checks for replaced jobs

## Architecture Benefits

### Replaced Job Patterns
The GitOps Lifecycle Management chart replaces problematic job patterns with:

1. **Helm Lifecycle Hooks**
   - Pre-install hooks for authentication setup
   - Pre-install hooks for database initialization
   - Post-install hooks for validation
   - Proper cleanup with TTL policies (300s)

2. **Service Discovery Controller**
   - Continuous reconciliation (5m interval)
   - Automatic cleanup of orphaned providers
   - Label-based service discovery (`authentik.io/proxy: "enabled"`)

3. **External Secrets Integration**
   - Proper 1Password Connect integration
   - Automatic secret refresh (15m interval)
   - Support for multiple secret types (tokens, OIDC, database credentials)

4. **Monitoring and Observability**
   - ServiceMonitor for Prometheus integration
   - Comprehensive metrics collection
   - Health checks and validation

## Deployment Configuration

### Key Configuration Values

```yaml
global:
  domain: "k8s.home.geoffdavis.com"
  authentikHost: "http://authentik-server.authentik.svc.cluster.local:9000"

authentication:
  enabled: true
  hooks:
    ttlSecondsAfterFinished: 300  # 5-minute cleanup

serviceDiscovery:
  enabled: true
  discovery:
    reconcileInterval: "5m"
    cleanupOrphaned: true

database:
  enabled: true
  hooks:
    postgresql:
      host: "homeassistant-postgresql-rw.home-automation.svc.cluster.local"

externalSecrets:
  enabled: true
  secretStore:
    name: "onepassword-connect"
    kind: "ClusterSecretStore"
```

### 1Password Integration

The chart integrates with the following 1Password entries:
- `home-ops-authentik-admin-token` → `authentik-admin-token` secret
- `home-ops-authentik-external-outpost-config` → `authentik-outpost-config` secret
- `home-ops-grafana-oidc-client-secret` → `grafana-oidc-secret` secret
- `home-ops-dashboard-oidc-client-secret` → `dashboard-oidc-secret` secret
- `home-ops-postgresql-superuser-credentials` → `postgresql-admin-credentials` secret

## Testing and Validation

### Pre-Deployment Validation

1. **Verify Prerequisites**
   ```bash
   # Check that dependencies are ready
   flux get kustomizations | grep -E "(sources|external-secrets|onepassword|authentik)"
   
   # Verify 1Password Connect is operational
   kubectl get pods -n onepassword-connect
   kubectl logs -n onepassword-connect -l app.kubernetes.io/name=onepassword-connect
   ```

2. **Check Existing Jobs Status**
   ```bash
   # Verify old jobs are not running
   kubectl get jobs -n authentik
   
   # Check for any stuck resources
   kubectl get pods -n authentik --field-selector=status.phase=Failed
   ```

### Deployment Validation

1. **Monitor Flux Deployment**
   ```bash
   # Watch the GitOps Lifecycle Management deployment
   flux get kustomizations infrastructure-gitops-lifecycle-management --watch
   
   # Check HelmRelease status
   flux get helmreleases -n flux-system gitops-lifecycle-management
   ```

2. **Verify Chart Components**
   ```bash
   # Check that the chart deployed successfully
   helm list -n flux-system | grep gitops-lifecycle-management
   
   # Verify external secrets are syncing
   kubectl get externalsecrets -A | grep -E "(authentik|gitops)"
   
   # Check service discovery controller
   kubectl get pods -l app.kubernetes.io/name=gitops-lifecycle-management
   ```

3. **Validate Functionality**
   ```bash
   # Check authentication hooks completed
   kubectl get jobs -l app.kubernetes.io/name=gitops-lifecycle-management
   
   # Verify database initialization
   kubectl logs -l app.kubernetes.io/component=database-init
   
   # Check service discovery
   kubectl logs -l app.kubernetes.io/component=service-discovery
   ```

### Post-Deployment Testing

1. **Authentication System**
   - Verify Authentik admin token is available and valid
   - Test OIDC client configurations for Grafana and Dashboard
   - Confirm external outpost configuration is applied

2. **Service Discovery**
   - Add `authentik.io/proxy: "enabled"` label to a test service
   - Verify automatic proxy provider creation
   - Test cleanup of orphaned providers

3. **Database Integration**
   - Verify Home Assistant database initialization
   - Test database connectivity from Home Assistant pods
   - Confirm proper credentials are available

## Troubleshooting

### Common Issues

1. **HelmRelease Fails to Deploy**
   ```bash
   # Check HelmRelease events
   kubectl describe helmrelease gitops-lifecycle-management -n flux-system
   
   # Check Helm controller logs
   kubectl logs -n flux-system -l app=helm-controller
   ```

2. **External Secrets Not Syncing**
   ```bash
   # Check external secrets status
   kubectl get externalsecrets -A
   kubectl describe externalsecret <secret-name> -n <namespace>
   
   # Verify 1Password Connect connectivity
   kubectl logs -n onepassword-connect -l app.kubernetes.io/name=onepassword-connect
   ```

3. **Service Discovery Issues**
   ```bash
   # Check service discovery controller logs
   kubectl logs -l app.kubernetes.io/component=service-discovery
   
   # Verify RBAC permissions
   kubectl auth can-i list services --as=system:serviceaccount:flux-system:gitops-lifecycle-management
   ```

### Recovery Procedures

1. **Rollback to Previous State**
   ```bash
   # Suspend the GitOps Lifecycle Management kustomization
   flux suspend kustomization infrastructure-gitops-lifecycle-management
   
   # Re-enable old jobs if needed (temporary)
   # Edit infrastructure/authentik-outpost-config/kustomization.yaml
   ```

2. **Clean Deployment**
   ```bash
   # Delete the HelmRelease
   kubectl delete helmrelease gitops-lifecycle-management -n flux-system
   
   # Clean up any stuck resources
   kubectl delete jobs -l app.kubernetes.io/name=gitops-lifecycle-management -A
   
   # Redeploy
   flux reconcile kustomization infrastructure-gitops-lifecycle-management
   ```

## Success Criteria

- ✅ GitOps Lifecycle Management HelmRelease deployed successfully
- ✅ All problematic jobs replaced with proper Helm lifecycle management
- ✅ External secrets syncing from 1Password Connect
- ✅ Service discovery controller operational
- ✅ Database initialization hooks working
- ✅ Authentication system integration maintained
- ✅ Proper cleanup policies in place (300s TTL)
- ✅ Monitoring and observability configured

## Next Steps

1. **Monitor System Stability**
   - Watch for any authentication issues
   - Monitor service discovery functionality
   - Verify cleanup policies are working

2. **Performance Optimization**
   - Adjust reconciliation intervals if needed
   - Optimize resource limits based on usage
   - Fine-tune cleanup policies

3. **Documentation Updates**
   - Update operational procedures
   - Document new troubleshooting procedures
   - Create runbooks for common tasks

## Integration with Existing Systems

The GitOps Lifecycle Management chart integrates seamlessly with:
- **External Authentik Outpost System**: Maintains compatibility with existing external outpost architecture
- **Home Assistant Stack**: Database initialization hooks replace the removed database-init-job
- **Monitoring Stack**: OIDC setup hooks replace individual OIDC setup jobs
- **Dashboard System**: Kong configuration maintained via existing init containers

This deployment represents a significant improvement in operational reliability and maintainability by replacing problematic job patterns with proper GitOps lifecycle management.